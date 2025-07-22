(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata
open Basic_locations

module LastWrites =
struct
  type t = VMemLocMap.t

  let initial = VMemLocMap.empty

  let join v lw1 lw2 =
    let merge _ v1 v2 =
      match v1, v2 with
      | Some v1, Some v2 when v1 == v2 -> v1
      | _ -> v
    in
    VMemLocMap.generic_join ~cache:NoCache ~symmetric:true ~idempotent:true
      ~decide:merge lw1 lw2

  let widen _ _ = Fixpoint

  let transfer (_, _, v) lw locs =
    MemLocSet.fold (fun ml -> VMemLocMap.add ml v) locs lw
end

module PtrTargets =
struct
  type t = MlsMemLocMap.t

  let initial formals =
    let add_arg_pt pt = function
      | { Cil_types.vtype = { tnode = TPtr _ } } as vi ->
        let target = MemLocSet.singleton MemLoc.InputMem in
        MlsMemLocMap.add (MemLoc.Var vi) target pt
      | _ -> pt
    in
    List.fold_left add_arg_pt MlsMemLocMap.empty formals

  let join _ pt1 pt2 =
    MlsMemLocMap.join ~cache:NoCache ~symmetric:true ~idempotent:true
      ~decide:(fun _ -> MemLocSet.union) pt1 pt2

  let widen pt1 pt2 =
    let included =
      MlsMemLocMap.binary_predicate NoCache UniversalPredicate
        ~decide_fast:(fun _ _ -> PUnknown)
        ~decide_fst:(fun _ _ -> false)
        ~decide_snd:(fun _ _ -> true)
        ~decide_both:(fun _ -> MemLocSet.subset)
        pt2 pt1
    in
    if included then Fixpoint
    else Widening pt2

  let transfer (_, e, _) pt
      (assigned_locs, target_locs, args_locs, ptr_args_locs) =
    let assign_ptr_target ?alloc_stmt force_join target_locs ml new_pt =
      let target_locs =
        match ml with
        | MemLoc.Var _ when not force_join -> target_locs
        | _ ->
          (* Heap blocks may represent several values if they are allocated in a
             loop, so we must always join targets in this case *)
          try MlsMemLocMap.find ml pt |> MemLocSet.union target_locs
          with Not_found -> target_locs
      in
      let target_locs =
        match alloc_stmt with
        | None -> target_locs
        | Some stmt -> MemLocSet.add (MemLoc.HeapBlk stmt) target_locs
      in
      MlsMemLocMap.add ml target_locs new_pt
    in
    let call_arg_ptr_target stmt = assign_ptr_target ~alloc_stmt:stmt true in

    let lval_is_compound (lval : Eva_ast.lval) =
      match snd lval.node with NoOffset -> false | _ -> true
    in

    match e.edge_transition with
    | Assign (lval, _, _) ->
      MemLocSet.fold
        (assign_ptr_target (lval_is_compound lval) target_locs)
        assigned_locs pt
    | Init (vi, _, _) ->
      if MemLocSet.is_empty target_locs then pt
      else
        MlsMemLocMap.add (MemLoc.Var vi) target_locs pt
    | Call (Some lval, _, _, stmt) ->
      let force_join = lval_is_compound lval in
      MemLocSet.fold
        (assign_ptr_target ~alloc_stmt:stmt force_join args_locs)
        assigned_locs pt
      |> MemLocSet.fold (call_arg_ptr_target stmt args_locs) ptr_args_locs
    | Call (None, _, _, stmt) ->
      MemLocSet.fold (call_arg_ptr_target stmt args_locs) ptr_args_locs pt
    | _ -> pt
end

type lw_and_pt = LastWrites.t * PtrTargets.t

module LwAndPt (Info : sig val include_guards : bool end) =
struct
  type t = lw_and_pt

  let initial formals = LastWrites.initial, PtrTargets.initial formals

  let join v (lw1, pt1) (lw2, pt2) =
    LastWrites.join v lw1 lw2, PtrTargets.join v pt1 pt2

  let widen (lw1, pt1) (lw2, pt2) =
    match LastWrites.widen lw1 lw2, PtrTargets.widen pt1 pt2 with
    | Fixpoint, Fixpoint -> Fixpoint
    | Widening st_d1, Fixpoint -> Widening (st_d1, pt2)
    | Fixpoint, Widening st_d2 -> Widening (lw2, st_d2)
    | Widening st_d1, Widening st_d2 -> Widening (st_d1, st_d2)

  let compute_locs e pt =
    let open MemLocUtil (struct let ptr_targets = pt end) in

    let add_arg_locs (target_locs, ptr_locs) (arg : Eva_ast.exp) =
      match arg.typ.tnode with
      | TPtr typ ->
        let locs = locs_of_exp arg |> recursive_locs in
        let ptr_locs =
          if typ_is_ptr typ then MemLocSet.union ptr_locs locs
          else ptr_locs
        in
        MemLocSet.union target_locs locs, ptr_locs
      | _ -> target_locs, ptr_locs
    in
    let rec guarded_locs (exp : Eva_ast.exp) =
      match exp.node with
      | CastE (_, exp) | UnOp (_, exp, _) -> guarded_locs exp
      | BinOp (_, exp1, exp2, _) ->
        MemLocSet.union (guarded_locs exp1) (guarded_locs exp2)
      | Lval lval -> locs_of_lval lval
      | _ -> MemLocSet.empty
    in

    let nolocs = MemLocSet.empty in
    match e.edge_transition with
    | Assign (lval, exp, _) ->
      let target_locs =
        if typ_is_ptr lval.typ then locs_of_exp exp else nolocs
      in
      locs_of_lval lval, target_locs, nolocs, nolocs
    | Init (vi, init, _) ->
      let assigned_locs = MemLocSet.singleton (MemLoc.Var vi) in
      assigned_locs, locs_of_init init, nolocs, nolocs
    | Call (lval, lhost, args, _) when not (Eva_ast.is_no_effect_frama_c_builtin lhost) ->
      let assigned_locs =
        match lval with Some lval -> locs_of_lval lval | None -> nolocs
      in
      let args_locs, ptr_args_locs =
        List.fold_left add_arg_locs (nolocs, nolocs) args
      in
      assigned_locs, nolocs, args_locs, ptr_args_locs
    | Guard (exp, _, _) when Info.include_guards ->
      guarded_locs exp, nolocs, nolocs, nolocs
    | _ -> nolocs, nolocs, nolocs, nolocs

  let transfer ((_, e, _) as edge) (lw, pt) =
    let (assigned_locs, _, args_locs, _) as all_locs = compute_locs e pt in
    let written_locs = MemLocSet.union assigned_locs args_locs in
    let lw = LastWrites.transfer edge lw written_locs
    and pt = PtrTargets.transfer edge pt all_locs in
    Some (lw, pt)
end
