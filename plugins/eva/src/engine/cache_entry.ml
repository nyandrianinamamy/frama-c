(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

type statement = Body of kernel_function

type observation = Cache_observation.observation

type footprint = Cache_observation.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

type dependencies = {
  sweeps : Base.Hptset.t;
  used_functions : (kernel_function * Body_access.call_mode) list;
  hint_generation : Widen_generation.t option;
  warn_categories : (string * Log.warn_status) list;
}

type rejection = [
  | `Key_differs | `Key_unclosed | `Sweep | `Recursion | `Hint_generation
  | `Watchpoint | `Automatic_cleanup | `Nested_delivery | `Warn_categories
]

let rejection_id : rejection -> string = function
  | `Key_differs -> "key-differs"
  | `Key_unclosed -> "key-unclosed"
  | `Sweep -> "sweep"
  | `Recursion -> "recursion"
  | `Hint_generation -> "hint-generation"
  | `Watchpoint -> "watchpoint"
  | `Automatic_cleanup -> "automatic-cleanup"
  | `Nested_delivery -> "nested-delivery"
  | `Warn_categories -> "warn-categories"

let return_block = function
  | Body kf -> Option.map Base.of_varinfo (Library_functions.get_retres_vi kf)

let with_return_block statement footprint =
  match return_block statement with
  | None -> footprint
  | Some b ->
    let add = Base.Hptset.add b in
    { footprint with written = add footprint.written;
                     written_exit = add footprint.written_exit;
                     written_sure = add footprint.written_sure }

let valid_footprint footprint =
  Base.Hptset.subset footprint.written_sure footprint.written_exit
  && Base.Hptset.subset footprint.written_exit footprint.written

let required_key ?reads footprint =
  let reads = Option.value ~default:footprint.read reads in
  Base.Hptset.union reads
    (Base.Hptset.diff footprint.written_exit footprint.written_sure)

module type Domain = sig
  type t
  val equal : t -> t -> bool
  val pretty : Format.formatter -> t -> unit
  val relate : Base.Hptset.t -> t -> Base.SetLattice.t
  val filter : Base.Hptset.t -> t -> t
  val reuse : Base.Hptset.t -> current_input:t -> previous_output:t -> t
end

module Make (Domain : Domain) = struct

  type t = {
    id : int;
    statement : statement;
    key : Base.Hptset.t;
    input : Domain.t;
    footprint : footprint;
    exit : (Partition.key * Domain.t) list;
    dependencies : dependencies option;
    observation : observation option;
    children : Cache_observation.child list;
    safety : Safety_part.t;
  }

  (* Whether [relate] relates [bases] only to blocks of [bases] in [state]. *)
  let is_closed bases state =
    Base.SetLattice.is_included
      (Domain.relate bases state) (Base.SetLattice.inject bases)

  let make ~id ?reads ?dependencies ?observation ?(children = [])
      ?(safety = Safety_part.empty) statement ~key ~input ~footprint ~exit =
    let footprint = with_return_block statement footprint in
    if not (valid_footprint footprint) then
      invalid_arg
        "Cache_entry.make: the written sets are not nested: \
         W_sure ⊆ W_exit ⊆ W fails";
    let missing = Base.Hptset.diff (required_key ?reads footprint) key in
    if not (Base.Hptset.is_empty missing) then
      Format.kasprintf invalid_arg
        "Cache_entry.make: the key does not contain %a, of R ∪ (W_exit \\ \
         W_sure)" Base.Hptset.pretty missing;
    if not (is_closed key input) then
      invalid_arg "Cache_entry.make: the key is not closed in the input";
    let kept = Base.Hptset.union key footprint.written in
    let exit = List.map (fun (k, s) -> k, Domain.filter kept s) exit in
    { id; statement; key; input = Domain.filter key input; footprint; exit;
      dependencies; observation; children; safety }

  let id e = e.id
  let with_id id e = { e with id }
  let statement e = e.statement
  let key e = e.key
  let input e = e.input
  let footprint e = e.footprint
  let exit e = e.exit
  let dependencies e = e.dependencies
  let safety e = e.safety
  let observation e = e.observation
  let children e = e.children

  let pretty_statement fmt = function
    | Body kf -> Format.fprintf fmt "body of %a" Kernel_function.pretty kf

  let pretty fmt e =
    let pretty_exit fmt (k, s) =
      Format.fprintf fmt "@[<v 2>exit state, partition key [%a]:@ %a@]"
        Partition.Key.pretty k Domain.pretty s
    in
    let pretty_input fmt input =
      if Base.Hptset.is_empty e.key
      then Format.pp_print_string fmt "input: none, the key is empty"
      else Format.fprintf fmt "@[<v 2>input:@ %a@]" Domain.pretty input
    in
    (* An entry without Safety writes prints as before the Safety part. *)
    let pretty_safety fmt = function
      | [] -> ()
      | safety ->
        Format.fprintf fmt "@ @[<v 2>safety:@ %a@]" Safety_part.pretty safety
    in
    Format.fprintf fmt
      "@[<v 2>entry %d, %a:@ key: %a@ %a@ read: %a@ written: %a@ \
       written on a path to an exit: %a@ surely overwritten: %a@ %a%a@]"
      e.id pretty_statement e.statement
      Base.Hptset.pretty e.key pretty_input e.input
      Base.Hptset.pretty e.footprint.read
      Base.Hptset.pretty e.footprint.written
      Base.Hptset.pretty e.footprint.written_exit
      Base.Hptset.pretty e.footprint.written_sure
      (Pretty_utils.pp_list ~sep:"@ " pretty_exit) e.exit
      pretty_safety e.safety

  type result = {
    rejected : (t * rejection) list;
    hit : (t * (Partition.key * Domain.t) list) option;
  }

  let check entry state =
    if not (Domain.equal (Domain.filter entry.key state) entry.input)
    then Error `Key_differs
    else if not (is_closed entry.key state)
    then Error `Key_unclosed
    else Ok ()

  (* Only the blocks of W_exit are taken from an exit state. A block of
     W \ W_exit is written only on paths that reach no exit: at an exit it
     holds its input value, which is that of the call, not the one that the
     stored exit state holds. *)
  let apply entry state =
    let written = entry.footprint.written_exit in
    let reuse (k, output) =
      k, Domain.reuse written ~current_input:state ~previous_output:output
    in
    List.map reuse entry.exit

  let find ~admit candidates state =
    let rec examine rejected = function
      | [] -> { rejected = List.rev rejected; hit = None }
      | entry :: younger ->
        match Result.bind (check entry state) (fun () -> admit entry state) with
        | Ok () ->
          let hit = Some (entry, apply entry state) in
          { rejected = List.rev rejected; hit }
        | Error reason -> examine ((entry, reason) :: rejected) younger
    in
    examine [] candidates
end

module Cvalue = struct
  include Make (Cvalue_domain.State)

  type Cache_observation.reference += Entry of t

  let reference t = Entry t

  let of_reference = function
    | Entry t -> Some t
    | _ -> None
end
