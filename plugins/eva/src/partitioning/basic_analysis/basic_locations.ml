(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

module MemLoc =
struct
  type elt =
    | Var of Eva_ast.varinfo
    | HeapBlk of Cil_types.stmt (* block on the heap *)
    | InputMem

  let initial_values = []
  let dependencies = []

  include Datatype.Make_with_collections
      (struct
        type t = elt
        let name = "Partition.Heuristics.MemLoc"
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
      end)

  let id = function
    | Var vi -> vi.vid
    | HeapBlk stmt -> Int.max_int / 2 + stmt.sid
    | InputMem -> Int.max_int
end

module MemLocSet = Hptset.Make (MemLoc) (MemLoc)
module VMemLocMap = Hptmap.Make (MemLoc) (Vertex) (MemLoc)
module MlsMemLocMap = Hptmap.Make (MemLoc) (MemLocSet) (MemLoc)

module MemLocUtil (Info : sig val ptr_targets : MlsMemLocMap.t end) =
struct
  open Eva_ast_types

  let rec locs_of_lval lval =
    match fst lval.node with
    | Var vi -> MemLocSet.singleton (MemLoc.Var vi)
    | Mem exp -> locs_of_exp exp
  and locs_of_exp exp =
    match exp.node with
    | CastE (_, exp) | UnOp (_, exp, _) | BinOp (_, exp, _, _) ->
      locs_of_exp exp
    | Lval lval -> locs_of_nested_lval lval
    | AddrOf lval | StartOf lval -> locs_of_lval lval
    | _ -> MemLocSet.empty
  and locs_of_nested_lval lval =
    match fst lval.node with
    | Var vi -> locs_of_deref (MemLoc.Var vi)
    | Mem exp ->
      MemLocSet.fold
        (fun ml acc -> MemLocSet.union (locs_of_deref ml) acc)
        (locs_of_exp exp) MemLocSet.empty
  and locs_of_deref ml =
    try MlsMemLocMap.find ml Info.ptr_targets
    with Not_found ->
    match ml with
    | MemLoc.Var { vglob = true } | MemLoc.InputMem ->
      MemLocSet.singleton MemLoc.InputMem
    | _ -> MemLocSet.empty
  and locs_of_init = function
    | SingleInit (exp, _) -> locs_of_exp exp
    | CompoundInit (_, init_l) ->
      List.fold_left
        (fun acc (_, init) -> MemLocSet.union acc (locs_of_init init))
        MemLocSet.empty init_l

  let recursive_locs locs =
    let add_targets loc acc =
      try MlsMemLocMap.find loc Info.ptr_targets |> MemLocSet.union acc
      with Not_found -> acc
    in
    let rec aux locs all_locs =
      let new_locs = MemLocSet.fold add_targets locs MemLocSet.empty in
      let new_locs = MemLocSet.diff new_locs all_locs in
      if MemLocSet.is_empty new_locs then
        locs
      else
        let all_locs = MemLocSet.union locs new_locs in
        MemLocSet.union all_locs (aux new_locs all_locs)
    in
    aux locs locs

  let typ_is_ptr typ =
    match typ.Cil_types.tnode with
    | TPtr _ -> true
    | _ -> false
end
