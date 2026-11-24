(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type decision =
  | Created
  | Reused of { weakened: bool }

type builtin =
  | Malloc
  | Calloc
  | Realloc

type record = { min_alloc: Z.t; max_alloc: Z.t }

type t =
  | Allocation of {
      block: Base.t;
      builtin: builtin;
      copied: Base.Hptset.t;
      policy: Eva_annotations.allocation_kind;
      stack: Callstack.t;
      rank: int option;
      size: Cvalue.V.t;
      typ: Cil_types.typ;
      decision: decision;
    }
  | Mutation of {
      block: Base.t;
      record: (record * record) option;
      weakened: bool;
      typ: (Cil_types.typ * Cil_types.typ) option;
    }
  | Removal of Base.t
  | Sweep of { block: Base.t; exact: bool }

let pretty_policy fmt policy =
  Format.pp_print_string fmt
    (match policy with
     | Eva_annotations.By_stack -> "by_stack"
     | Fresh -> "fresh"
     | Fresh_weak -> "fresh_weak"
     | Imprecise -> "imprecise")

let pretty_decision fmt = function
  | Created -> Format.pp_print_string fmt "created"
  | Reused { weakened = false } -> Format.pp_print_string fmt "reused"
  | Reused { weakened = true } -> Format.pp_print_string fmt "reused, weakened"

let pretty_record fmt { min_alloc; max_alloc } =
  Format.fprintf fmt "[%a..%a]" Z.pretty min_alloc Z.pretty max_alloc

(* Nothing is printed for [malloc]. *)
let pretty_builtin fmt (builtin, copied) =
  match builtin with
  | Malloc -> ()
  | Calloc -> Format.fprintf fmt ",@ by calloc"
  | Realloc when Base.Hptset.is_empty copied ->
    Format.fprintf fmt ",@ by realloc,@ copying nothing"
  | Realloc ->
    Format.fprintf fmt ",@ by realloc,@ copying %a"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ") Base.pretty)
      (Base.Hptset.elements copied)

let pretty fmt = function
  | Allocation { block; builtin; copied; policy; stack; rank; size; typ;
                 decision } ->
    Format.fprintf fmt
      "@[<hov 2>allocation of %a:@ policy %a,@ stack %a,@ %a@ size %a,@ \
       type %a,@ %a%a@]"
      Base.pretty block pretty_policy policy Callstack.pretty stack
      (fun fmt -> function
         | None -> Format.pp_print_string fmt "no rank,"
         | Some rank -> Format.fprintf fmt "rank %d," rank)
      rank Cvalue.V.pretty size Printer.pp_typ typ pretty_decision decision
      pretty_builtin (builtin, copied)
  | Mutation { block; record; weakened; typ } ->
    let changes =
      Option.to_list
        (Option.map
           (fun (before, after) fmt ->
              Format.fprintf fmt "record %a to %a"
                pretty_record before pretty_record after)
           record)
      @ (if weakened then [ fun fmt -> Format.fprintf fmt "weakened" ] else [])
      @ Option.to_list
        (Option.map
           (fun (before, after) fmt ->
              Format.fprintf fmt "type %a to %a"
                Printer.pp_typ before Printer.pp_typ after)
           typ)
    in
    Format.fprintf fmt "@[<hov 2>validity mutation of %a:@ %a@]"
      Base.pretty block
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (fun fmt change -> change fmt))
      changes
  | Removal block -> Format.fprintf fmt "removal of %a" Base.pretty block
  | Sweep { block; exact } ->
    Format.fprintf fmt "sweep of %a, %s"
      Base.pretty block (if exact then "exact" else "joined")

let enabled () = Parameters.HitLog.get ()

let sinks = ref []

let register_sink f = sinks := !sinks @ [ f ]

let emit ?point e = List.iter (fun f -> f ?point e) !sinks

let whole_heap_readers = ref []

let register_whole_heap_reader f =
  whole_heap_readers := !whole_heap_readers @ [ f ]

let read_whole_heap () =
  if enabled () then List.iter (fun f -> f ()) !whole_heap_readers

let widening_point = ref None

let at_widening stmt f =
  if enabled () then begin
    let outer = !widening_point in
    widening_point := Some stmt;
    Fun.protect ~finally:(fun () -> widening_point := outer) f
  end
  else f ()

(* The widening raises [max_alloc] only: the type and the strength of the
   block do not change. *)
let () =
  Lmap.register_validity_widening_hook
    (fun block ~old_max_alloc ->
       if enabled () then
         match Base.validity block with
         | Variable { min_alloc; max_alloc } ->
           let record =
             Some ({ min_alloc; max_alloc = old_max_alloc },
                   { min_alloc; max_alloc })
           in
           let point = !widening_point in
           emit ?point (Mutation { block; record; weakened = false; typ = None })
         | Known _ | Unknown _ | Invalid | Empty -> ())
