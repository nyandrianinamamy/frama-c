(* Device of the tests of the numbered form of an entry (#124).

   In the analysis with -eva-hit-log, each time memexec stores a call, it
   numbers the allocated blocks of the entry of the call (Eva's [Numbering])
   and prints:
   - each numbered block, with how the numbering discovered it, whether it
     is a block of the key, and its strength, validity record, type and
     kind at the store;
   - the numbered form of the entry: its arguments, its key, its start state
     on the key and its states at the exits, each with its clobbered set.
     A memory map is printed interval by interval, in bits, with the size
     and the offset of the value when the value does not fill the interval
     exactly once and is not isotropic; nothing reads the type of a block
     to print it;
   - whether rewriting the numbered form back gives the entry (the round
     trip), and which parts differ if not;
   - whether an earlier entry of the same function has the same numbered
     form and the same blocks, except for their names and discovery.

   An entry with no allocated block is printed on one line.

   For the function [unreached], it also numbers the entry again with, as
   candidates, the blocks numbered in earlier entries of the run that this
   entry does not number. When the main function is [unreached_main], it
   checks that the numbering refuses an argument, then a block of the key,
   that may point to an unknown set of blocks.

   After the analyses, it prints the number of entries, of entries with a
   numbered block, of entries without numbered form, of round trips that
   differ, and of placeholders found in the entries that memexec gives. *)

module Numbering = Eva__Numbering

let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  String.map (fun c -> if c = '\n' then ' ' else c) (Buffer.contents buffer)

let pp_list ?(empty = "none") pp fmt = function
  | [] -> Format.pp_print_string fmt empty
  | list ->
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> Format.pp_print_string fmt ", ") pp fmt list

(* ----- Printing --------------------------------------------------------- *)

let pp_bases fmt bases =
  pp_list Base.pretty fmt (List.sort Base.compare (Base.Hptset.elements bases))

let pp_argument fmt = function
  | `Bottom -> Format.pp_print_string fmt "bottom"
  | `Value v -> Cvalue.V.pretty fmt v

let pp_offsetmap fmt offsetmap =
  let intervals =
    Cvalue.V_Offsetmap.fold
      (fun interval value acc -> (interval, value) :: acc) offsetmap []
  in
  let pp_interval fmt ((lo, hi), (v, size, offset)) =
    Format.fprintf fmt "[%a..%a] %a" Z.pretty lo Z.pretty hi
      Cvalue.V_Or_Uninitialized.pretty v;
    if not (Cvalue.V_Or_Uninitialized.is_isotropic v
            || Z.equal size (Z.succ (Z.sub hi lo))
               && Abstract_interp.Rel.is_zero offset)
    then
      Format.fprintf fmt " (size %a, offset %a)"
        Z.pretty size Abstract_interp.Rel.pretty offset
  in
  pp_list pp_interval fmt (List.rev intervals)

let pp_clobbered fmt { Eva__Locals_scoping.clob } =
  match clob with
  | Base.SetLattice.Top -> Format.pp_print_string fmt "top"
  | Base.SetLattice.Set bases -> pp_bases fmt bases

let print_state label (model, clobbered) =
  Format.printf "  %s, clobbered set %s:@."
    label (one_line pp_clobbered clobbered);
  match model with
  | Cvalue.Model.Top -> Format.printf "    top@."
  | Cvalue.Model.Bottom -> Format.printf "    bottom@."
  | Cvalue.Model.Map map ->
    let bindings =
      Cvalue.Model.fold (fun base offsm acc -> (base, offsm) :: acc) map []
    in
    List.iter
      (fun (base, offsetmap) ->
         Format.printf "    %s: %s@." (one_line Base.pretty base)
           (one_line pp_offsetmap offsetmap))
      (List.sort (fun (b1, _) (b2, _) -> Base.compare b1 b2) bindings)

let pp_discovery fmt = function
  | Numbering.Argument i -> Format.fprintf fmt "argument %d" i
  | Content base -> Format.fprintf fmt "content of %a" Base.pretty base
  | Candidate -> Format.pp_print_string fmt "candidate"
  | No_root -> Format.pp_print_string fmt "key block reached from no root"

let pp_kind fmt = function
  | Base.Malloc -> Format.pp_print_string fmt "malloc"
  | Base.VLA -> Format.pp_print_string fmt "variable-length array"
  | Base.Alloca -> Format.pp_print_string fmt "alloca"

(* The strength, validity record, type and kind of a block, now. *)
let describe base =
  match base with
  | Base.Allocated (vi, kind, validity) ->
    Format.asprintf "%s, record %a, type %a, %a"
      (if Base.is_weak base then "weak" else "strong")
      Base.pretty_validity validity Printer.pp_typ vi.vtype pp_kind kind
  | _ -> "not allocated"

let print_blocks ~key numbering =
  List.iteri
    (fun n (base, _weak, discovery) ->
       Format.printf "    #%d: %a, %a%s; %s@." n Base.pretty base
         pp_discovery discovery
         (if Base.Hptset.mem base key then ", in the key" else "")
         (describe base))
    (Numbering.blocks numbering)

let print_entry (entry: Numbering.entry) =
  Format.printf "  arguments: %s@."
    (one_line (pp_list pp_argument) entry.args);
  Format.printf "  key: %s@." (one_line pp_bases entry.key);
  print_state "start" entry.start;
  List.iteri
    (fun i state -> print_state (Printf.sprintf "exit %d" (i + 1)) state)
    entry.exits

(* ----- Checks ----------------------------------------------------------- *)

let equal_argument a b =
  match a, b with
  | `Bottom, `Bottom -> true
  | `Value a, `Value b -> Cvalue.V.equal a b
  | (`Bottom | `Value _), _ -> false

let equal_clobbered c1 c2 =
  Base.SetLattice.equal c1.Eva__Locals_scoping.clob c2.Eva__Locals_scoping.clob

(* The parts of two entries that differ. *)
let differences (e1: Numbering.entry) (e2: Numbering.entry) =
  let state label (m1, c1) (m2, c2) =
    (if Cvalue.Model.equal m1 m2 then [] else [ label ])
    @ if equal_clobbered c1 c2 then [] else [ label ^ " clobbered set" ]
  in
  (if List.equal equal_argument e1.args e2.args then [] else [ "arguments" ])
  @ (if Base.Hptset.equal e1.key e2.key then [] else [ "key" ])
  @ state "start" e1.start e2.start
  @ (if List.compare_lengths e1.exits e2.exits <> 0 then [ "exits" ]
     else
       List.concat
         (List.mapi
            (fun i (s1, s2) -> state (Printf.sprintf "exit %d" (i + 1)) s1 s2)
            (List.combine e1.exits e2.exits)))

(* The bases of an entry, wherever they appear. *)
let bases_of_entry (entry: Numbering.entry) =
  let of_value v acc =
    match Cvalue.V.get_bases v with
    | Base.SetLattice.Top -> acc
    | Base.SetLattice.Set bases -> Base.Hptset.union bases acc
  in
  let of_state acc (model, { Eva__Locals_scoping.clob }) =
    let acc =
      match clob with
      | Base.SetLattice.Top -> acc
      | Base.SetLattice.Set bases -> Base.Hptset.union bases acc
    in
    match model with
    | Cvalue.Model.Top | Cvalue.Model.Bottom -> acc
    | Cvalue.Model.Map map ->
      Cvalue.Model.fold
        (fun base offsetmap acc ->
           Cvalue.V_Offsetmap.fold_on_values
             (fun v -> of_value (Cvalue.V_Or_Uninitialized.get_v v))
             offsetmap (Base.Hptset.add base acc))
        map acc
  in
  let acc =
    List.fold_left
      (fun acc -> function `Bottom -> acc | `Value v -> of_value v acc)
      entry.key entry.args
  in
  List.fold_left of_state acc (entry.start :: entry.exits)

(* ----- Hook ------------------------------------------------------------- *)

let entries = ref 0
let numbered_entries = ref 0
let refused = ref 0
let failed_round_trips = ref 0
let placeholders_seen = ref 0

(* The numbered forms printed, by function: the number of the cache entry,
   the numbered form and the descriptions of its blocks. *)
let forms : (string, (int * Numbering.entry * string list) list) Hashtbl.t =
  Hashtbl.create 7

(* The blocks numbered in earlier entries of the run. *)
let seen_blocks = ref Base.Hptset.empty

let check_candidates (entry: Numbering.entry) numbering =
  let candidates =
    Base.Hptset.filter
      (fun base -> Option.is_none (Numbering.number numbering base))
      !seen_blocks
  in
  let candidates = List.sort Base.compare (Base.Hptset.elements candidates) in
  Format.printf "  with the blocks of earlier entries as candidates, %s:@."
    (one_line (pp_list Base.pretty) candidates);
  match Numbering.number_entry ~candidates entry with
  | Ok (numbering, _) -> print_blocks ~key:entry.key numbering
  | Error _ -> Format.printf "    no numbered form@."

let print_error = function
  | Numbering.Unknown ->
    Format.printf
      "  no numbered form: a value of the arguments or of the key may point \
       to an unknown set of blocks@."
  | Unnumbered bases ->
    Format.printf "  no numbered form: blocks left unnumbered: %s@."
      (one_line pp_bases bases)

let check_entry kf id (entry: Numbering.entry) =
  incr entries;
  let name = Kernel_function.get_name kf in
  let placeholders =
    Base.Hptset.filter
      (fun b -> Option.is_some (Numbering.placeholder_number b))
      (bases_of_entry entry)
  in
  if not (Base.Hptset.is_empty placeholders) then begin
    placeholders_seen := !placeholders_seen + Base.Hptset.cardinal placeholders;
    Format.printf "Placeholders in the entry %d of %s: %s@." id name
      (one_line pp_bases placeholders)
  end;
  match Numbering.number_entry ~candidates:[] entry with
  | Error error ->
    incr refused;
    Format.printf "Cache entry %d, %s:@." id name;
    print_error error
  | Ok (numbering, numbered) ->
    let back = Numbering.rewrite (Numbering.of_numbers numbering) numbered in
    let differ = differences back entry in
    if differ <> [] then incr failed_round_trips;
    let round_trip =
      match differ with
      | [] -> "equal"
      | parts -> "DIFFERS in " ^ String.concat ", " parts
    in
    match Numbering.blocks numbering with
    | [] ->
      Format.printf "Cache entry %d, %s: no allocated block, round trip %s.@."
        id name round_trip
    | blocks ->
      incr numbered_entries;
      Format.printf "Cache entry %d, %s:@." id name;
      Format.printf "  numbered blocks:@.";
      print_blocks ~key:entry.key numbering;
      print_entry numbered;
      Format.printf "  round trip: %s@." round_trip;
      let descriptions = List.map (fun (b, _, _) -> describe b) blocks in
      let previous = try Hashtbl.find forms name with Not_found -> [] in
      begin
        match
          List.find_opt
            (fun (_, form, desc) ->
               Numbering.equal_entry form numbered && desc = descriptions)
            (List.rev previous)
        with
        | Some (previous_id, _, _) ->
          Format.printf "  same numbered form as the cache entry %d@."
            previous_id
        | None -> Format.printf "  new numbered form@."
      end;
      Hashtbl.replace forms name ((id, numbered, descriptions) :: previous);
      if name = "unreached" then check_candidates entry numbering;
      List.iter
        (fun (b, _, _) -> seen_blocks := Base.Hptset.add b !seen_blocks)
        blocks

let () = Eva__Mem_exec.register_store_hook check_entry

(* ----- Unknown targets -------------------------------------------------- *)

(* The numbering of an entry with an argument, then a block of the key, that
   may point to an unknown set of blocks. *)
let check_unknown () =
  let top = Cvalue.V.top in
  let no_state = Cvalue.Model.empty_map, Eva__Locals_scoping.bottom () in
  let entry =
    Numbering.{ args = [ `Value top ]; key = Base.Hptset.empty;
                start = no_state; exits = [] }
  in
  let print label = function
    | Ok _ -> Format.printf "%s: numbered form@." label
    | Error Numbering.Unknown ->
      Format.printf "%s: no numbered form, unknown targets@." label
    | Error (Unnumbered _) -> Format.printf "%s: blocks left@." label
  in
  print "Numbering of an argument that may point to any block"
    (Numbering.number_entry ~candidates:[] entry);
  let vi =
    Cil.makeGlobalVar ~source:false "unknown_slot" Cil_const.voidPtrType
  in
  let size = Z.of_int 32 in
  let slot = Base.register_memory_var vi (Base.Known (Z.zero, Z.pred size)) in
  let offsetmap =
    Cvalue.V_Offsetmap.create ~size
      (Cvalue.V_Or_Uninitialized.initialized top) ~size_v:size
  in
  let model = Cvalue.Model.add_base slot offsetmap Cvalue.Model.empty_map in
  let entry =
    Numbering.{ args = []; key = Base.Hptset.singleton slot;
                start = model, Eva__Locals_scoping.bottom (); exits = [] }
  in
  print "Numbering of a block of the key that may point to any block"
    (Numbering.number_entry ~candidates:[] entry)

let () =
  Boot.Main.extend
    (fun () ->
       if Kernel.MainFunction.get () = "unreached_main" then check_unknown ();
       Format.printf
         "Stored entries: %d; with a numbered block: %d; without numbered \
          form: %d; round trips that differ: %d; placeholders in the entries \
          given by memexec: %d.@."
         !entries !numbered_entries !refused !failed_round_trips
         !placeholders_seen)
