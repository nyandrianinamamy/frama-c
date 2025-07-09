(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata
open Basic_locations
open Basic_analysis

type mem_access =
  | Reads of MemLoc.t
  | Writes_to of MemLoc.t * bool

let get_edge_accesses (automaton : automaton) interproc_args states =
  let e_accesses = Edge.Hashtbl.create 4 in
  let register_accesses (v, e, _) =
    let open Eva_ast_types in

    let ptr_targets =
      match Vertex.Hashtbl.find_opt states v with
      | None -> MlsMemLocMap.empty
      | Some (_, ptr_targets) -> ptr_targets
    in
    let open MemLocUtil (struct let ptr_targets = ptr_targets end) in

    let to_reads ml = Reads ml
    and to_writes { node = _, offset } ml =
      let is_compound = match offset with NoOffset -> false | _ -> true in
      Writes_to (ml, is_compound)
    and to_arg_writes ml = Writes_to (ml, true) in
    let locs_to_acc conv locs =
      MemLocSet.fold (fun ml l -> conv ml :: l) locs []
    in

    let rec offset_accesses = function
      | NoOffset -> []
      | Field (_, offset) -> offset_accesses offset
      | Index (exp, offset) -> exp_accesses exp @ offset_accesses offset
    and lhost_accesses = function
      | Var vi -> [Reads (MemLoc.Var vi)]
      | Mem exp -> locs_to_acc to_reads (locs_of_exp exp) @ exp_accesses exp
    and lval_accesses { node = lhost, offset } =
      lhost_accesses lhost @ offset_accesses offset
    and written_lval_accesses ({ node = lhost, offset } as lval) =
      (match lhost with Mem exp -> exp_accesses exp | _ -> []) @
      locs_to_acc (to_writes lval) (locs_of_lval lval) @
      offset_accesses offset
    and exp_accesses { node } =
      match node with
      | Lval lval | AddrOf lval | StartOf lval -> lval_accesses lval
      | UnOp (_, exp, _) | CastE (_, exp) -> exp_accesses exp
      | BinOp (_, exp1, exp2, _) -> exp_accesses exp1 @ exp_accesses exp2
      | _ -> []
    and arg_accesses exp =
      let ptr_accesses =
        match exp.node with
        | Lval lval when typ_is_ptr lval.typ ->
          let locs = locs_of_nested_lval lval |> recursive_locs in
          locs_to_acc to_reads locs @ locs_to_acc to_arg_writes locs
        | AddrOf lval | StartOf lval when typ_is_ptr lval.typ ->
          let locs = locs_of_lval lval |> recursive_locs in
          locs_to_acc to_reads locs @ locs_to_acc to_arg_writes locs
        | AddrOf lval | StartOf lval ->
          locs_to_acc to_arg_writes (locs_of_lval lval)
        | _ -> []
      in
      ptr_accesses @ exp_accesses exp
    and init_accesses = function
      | SingleInit (exp, _) -> exp_accesses exp
      | CompoundInit (_, init_l) ->
        List.concat_map (fun (_, init) -> init_accesses init) init_l
    in

    let arg_ret_acc vi =
      if typ_is_ptr vi.Cil_types.vtype then
        locs_of_deref (MemLoc.Var vi)
        |> recursive_locs
        |> locs_to_acc to_reads
      else []
    and ret_ptr_acc exp =
      if typ_is_ptr exp.typ then
        locs_of_exp exp
        |> recursive_locs
        |> locs_to_acc to_reads
      else []
    in

    let accesses = match e.edge_transition with
      | Return (None, _) when interproc_args <> None ->
        List.concat_map arg_ret_acc (Option.get interproc_args)
      | Return (Some exp, _) when interproc_args <> None ->
        List.concat_map arg_ret_acc (Option.get interproc_args) @
        ret_ptr_acc exp @ exp_accesses exp
      | Return (Some exp, _) -> exp_accesses exp
      | Guard (exp, _, _) -> exp_accesses exp
      | Assign (lval, exp, _) -> written_lval_accesses lval @ exp_accesses exp
      | Call (lval, lhost, args, _) when not (is_no_effect_frama_c_builtin lhost) ->
        (match lval with
         | None -> []
         | Some lval -> written_lval_accesses lval) @
        lhost_accesses lhost @ List.concat_map arg_accesses args
      | Init (vi, init, _) ->
        Writes_to (MemLoc.Var vi, false) :: init_accesses init
      | _ -> []
    in
    Edge.Hashtbl.add e_accesses e accesses;
  in
  G.iter_edges_e register_accesses automaton.graph;
  e_accesses
