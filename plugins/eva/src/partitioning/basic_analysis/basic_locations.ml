(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module MemLoc =
struct
  type t =
    | Var of Eva_ast.varinfo
    | HeapBlk of Cil_types.stmt
    | InputMem

  module DatatypeInfo =
  struct
    type nonrec t = t
    let name = "Partition.Basic_analysis.MemLoc"
    let reprs = [InputMem]
    let structural_descr = Structural_descr.t_unknown
    let compare ml1 ml2 =
      match ml1, ml2 with
      | Var vi1, Var vi2 -> Cil_datatype.Varinfo.compare vi1 vi2
      | HeapBlk stmt1, HeapBlk stmt2 ->
        Cil_datatype.Stmt.compare stmt1 stmt2
      | _, _ -> compare ml1 ml2
    let equal ml1 ml2 = compare ml1 ml2 = 0
    let hash = function
      | Var vi -> Hashtbl.hash (1, Cil_datatype.Varinfo.hash vi)
      | HeapBlk stmt -> Hashtbl.hash (2, Cil_datatype.Stmt.hash stmt)
      | InputMem -> Hashtbl.hash 3
    let copy = Fun.id
    let rehash = Fun.id
    let mem_project = Datatype.never_any_project
    let pretty fmt = function
      | Var vi -> Cil_datatype.Varinfo.pretty fmt vi
      | HeapBlk stmt ->
        Format.fprintf fmt "[%a]" Cil_datatype.Stmt.pretty stmt
      | InputMem -> Format.fprintf fmt "#"
  end

  include (Datatype.Make (DatatypeInfo) : Datatype.S with type t := t)

  let initial_values = []
  let dependencies = []

  let id = function
    | Var vi -> vi.vid
    | HeapBlk stmt -> Int.max_int / 2 + stmt.sid
    | InputMem -> Int.max_int
end

include MemLoc

module Set = Hptset.Make (MemLoc) (MemLoc)
module Map (V : Datatype.S) = Hptmap.Make (MemLoc) (V) (MemLoc)
module SetMap = Map (Set)

module Util (Info : sig val ptr_targets : SetMap.t end) =
struct
  open Eva_ast_types

  let rec locs_of_lval lval =
    match fst lval.node with
    | Var vi -> Set.singleton (MemLoc.Var vi)
    | Mem exp -> locs_of_exp exp
  and locs_of_exp exp =
    match exp.node with
    | CastE (_, exp) | UnOp (_, exp, _) | BinOp (_, exp, _, _) ->
      locs_of_exp exp
    | Lval lval -> locs_of_nested_lval lval
    | AddrOf lval | StartOf lval -> locs_of_lval lval
    | _ -> Set.empty
  and locs_of_nested_lval lval =
    match fst lval.node with
    | Var vi -> locs_of_deref (MemLoc.Var vi)
    | Mem exp ->
      Set.fold
        (fun ml acc -> Set.union (locs_of_deref ml) acc)
        (locs_of_exp exp) Set.empty
  and locs_of_deref ml =
    try SetMap.find ml Info.ptr_targets
    with Not_found ->
    match ml with
    | MemLoc.Var { vglob = true } | InputMem ->
      Set.singleton InputMem
    | _ -> Set.empty
  and locs_of_init = function
    | SingleInit (exp, _) -> locs_of_exp exp
    | CompoundInit (_, init_l) ->
      List.fold_left
        (fun acc (_, init) -> Set.union acc (locs_of_init init))
        Set.empty init_l

  let recursive_locs locs =
    let add_targets loc acc =
      try SetMap.find loc Info.ptr_targets |> Set.union acc
      with Not_found -> acc
    in
    let rec aux locs all_locs =
      let new_locs = Set.fold add_targets locs Set.empty in
      let new_locs = Set.diff new_locs all_locs in
      if Set.is_empty new_locs then
        locs
      else
        let all_locs = Set.union locs new_locs in
        Set.union all_locs (aux new_locs all_locs)
    in
    aux locs locs

  let typ_is_ptr typ =
    match typ.Cil_types.tnode with
    | TPtr _ -> true
    | _ -> false
end
