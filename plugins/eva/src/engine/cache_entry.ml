(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

type statement = Body of kernel_function

type footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
}

type rejection = [ `Key_differs | `Key_unclosed ]

let rejection_id : rejection -> string = function
  | `Key_differs -> "key-differs"
  | `Key_unclosed -> "key-unclosed"

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
  }

  (* Whether [relate] relates [bases] only to blocks of [bases] in [state]. *)
  let is_closed bases state =
    Base.SetLattice.is_included
      (Domain.relate bases state) (Base.SetLattice.inject bases)

  let return_block = function
    | Body kf -> Option.map Base.of_varinfo (Library_functions.get_retres_vi kf)

  let make ~id statement ~key ~input ~footprint ~exit =
    if not (is_closed key input) then
      invalid_arg "Cache_entry.make: the key is not closed in the input";
    let written =
      match return_block statement with
      | None -> footprint.written
      | Some b -> Base.Hptset.add b footprint.written
    in
    let footprint = { footprint with written } in
    let kept = Base.Hptset.union key written in
    let exit = List.map (fun (k, s) -> k, Domain.filter kept s) exit in
    { id; statement; key; input = Domain.filter key input; footprint; exit }

  let id e = e.id
  let statement e = e.statement
  let key e = e.key
  let input e = e.input
  let footprint e = e.footprint
  let exit e = e.exit

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
    Format.fprintf fmt
      "@[<v 2>entry %d, %a:@ key: %a@ %a@ read: %a@ written: %a@ %a@]"
      e.id pretty_statement e.statement
      Base.Hptset.pretty e.key pretty_input e.input
      Base.Hptset.pretty e.footprint.read
      Base.Hptset.pretty e.footprint.written
      (Pretty_utils.pp_list ~sep:"@ " pretty_exit) e.exit

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

  let apply entry state =
    let written = entry.footprint.written in
    let reuse (k, output) =
      k, Domain.reuse written ~current_input:state ~previous_output:output
    in
    List.map reuse entry.exit

  let find candidates state =
    let rec examine rejected = function
      | [] -> { rejected = List.rev rejected; hit = None }
      | entry :: younger ->
        match check entry state with
        | Ok () ->
          let hit = Some (entry, apply entry state) in
          { rejected = List.rev rejected; hit }
        | Error reason -> examine ((entry, reason) :: rejected) younger
    in
    examine [] candidates
end
