(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata
open Basic_locations

(* The same function as in auto_loop_unroll.ml *)
let is_no_effect_frama_c_builtin (f:Eva_ast.lhost) =
  match f with
  | Var vi ->
    Ast_info.start_with_frama_c_builtin vi.vname
  | _ -> false

type written_locs = {
  last_writes: VMemLocMap.t;
  ptr_targets: MlsMemLocMap.t;
}

module WrittenLocs (Info : sig val include_guards : bool end) =
struct
  type t = written_locs

  let initial formals =
    let add_arg_ptr_target ptr_targets = function
      | { Cil_types.vtype = { tnode = TPtr _ } } as vi ->
        let target = MemLocSet.singleton MemLoc.InputMem in
        MlsMemLocMap.add (MemLoc.Var vi) target ptr_targets
      | _ -> ptr_targets
    in
    let ptr_targets =
      List.fold_left add_arg_ptr_target MlsMemLocMap.empty formals
    in
    { last_writes = VMemLocMap.empty; ptr_targets }

  let join v wl1 wl2 =
    let merge_writes _ v1 v2 =
      match v1, v2 with
      | Some v1, Some v2 when v1 == v2 -> v1
      | _ -> v
    in
    let merge_targets _ = MemLocSet.union in
    let last_writes =
      VMemLocMap.generic_join ~cache:NoCache ~symmetric:true ~idempotent:true
        ~decide:merge_writes wl1.last_writes wl2.last_writes
    in
    let ptr_targets =
      MlsMemLocMap.join ~cache:NoCache ~symmetric:true ~idempotent:true
        ~decide:merge_targets wl1.ptr_targets wl2.ptr_targets
    in
    { last_writes; ptr_targets }

  let widen wl1 wl2 =
    let included =
      MlsMemLocMap.binary_predicate NoCache UniversalPredicate
        ~decide_fast:(fun _ _ -> PUnknown)
        ~decide_fst:(fun _ _ -> false)
        ~decide_snd:(fun _ _ -> true)
        ~decide_both:(fun _ -> MemLocSet.subset)
        wl2.ptr_targets wl1.ptr_targets
    in
    if included then Fixpoint
    else Widening wl2

  let transfer (_, e, v) wl =
    let open Eva_ast_types in
    let open MemLocUtil (struct let ptr_targets = wl.ptr_targets end) in

    let add_arg_locs (target_locs, ptr_locs) arg =
      match arg.typ.tnode with
      | TPtr typ ->
        let locs = locs_of_exp arg |> recursive_locs in
        let ptr_locs =
          if typ_is_ptr typ then MemLocSet.union locs ptr_locs
          else ptr_locs
        in
        MemLocSet.union target_locs locs, ptr_locs
      | _ -> target_locs, ptr_locs
    in
    let assign_ptr_target ?alloc_stmt force_join target_locs ml pt =
      let target_locs =
        match ml with
        | MemLoc.Var _ when not force_join -> target_locs
        | _ ->
          (* Heap blocks may represent several values if they are allocated in a
             loop, so we must always join targets in this case *)
          try MlsMemLocMap.find ml wl.ptr_targets |> MemLocSet.union target_locs
          with Not_found -> target_locs
      in
      let target_locs =
        match alloc_stmt with
        | None -> target_locs
        | Some stmt -> MemLocSet.add (MemLoc.HeapBlk stmt) target_locs
      in
      MlsMemLocMap.add ml target_locs pt
    in
    let call_arg_ptr_target stmt target_locs ml pt =
      assign_ptr_target ~alloc_stmt:stmt true target_locs ml pt
    in

    let lval_is_compound lval =
      match snd lval.node with NoOffset -> false | _ -> true
    in
    let write_v ml = VMemLocMap.add ml v in

    let rec guarded_locs exp =
      match exp.node with
      | CastE (_, exp) | UnOp (_, exp, _) -> guarded_locs exp
      | BinOp (_, exp1, exp2, _) ->
        MemLocSet.union (guarded_locs exp1) (guarded_locs exp2)
      | Lval lval -> locs_of_lval lval
      | _ -> MemLocSet.empty
    in

    let wl = match e.edge_transition with
      | Assign (lval, exp, _) ->
        let locs = locs_of_lval lval in
        let last_writes = MemLocSet.fold write_v locs wl.last_writes in
        let ptr_targets =
          if typ_is_ptr lval.typ then
            let target_locs = locs_of_exp exp in
            MemLocSet.fold
              (assign_ptr_target (lval_is_compound lval) target_locs)
              locs wl.ptr_targets
          else
            wl.ptr_targets
        in
        { last_writes; ptr_targets }
      | Init (vi, init, _) ->
        let last_writes = write_v (MemLoc.Var vi) wl.last_writes in
        let ptr_targets =
          if typ_is_ptr vi.vtype then
            MlsMemLocMap.add (MemLoc.Var vi) (locs_of_init init) wl.ptr_targets
          else
            wl.ptr_targets
        in
        { last_writes; ptr_targets }
      | Call (Some lval, _, args, stmt) ->
        let locs = locs_of_lval lval in
        let args_locs, ptr_args_locs =
          List.fold_left add_arg_locs (MemLocSet.empty, MemLocSet.empty) args
        in
        let last_writes =
          MemLocSet.fold write_v locs wl.last_writes
          |> MemLocSet.fold write_v args_locs
        in
        let ptr_targets =
          if typ_is_ptr lval.typ then
            let force_join = lval_is_compound lval in
            MemLocSet.fold
              (assign_ptr_target ~alloc_stmt:stmt force_join args_locs)
              locs wl.ptr_targets
          else
            wl.ptr_targets
        in
        let ptr_targets =
          MemLocSet.fold
            (call_arg_ptr_target stmt args_locs)
            ptr_args_locs ptr_targets
        in
        { last_writes; ptr_targets }
      | Call (None, lhost, args, stmt) when not (is_no_effect_frama_c_builtin lhost) ->
        let args_locs, ptr_args_locs =
          List.fold_left add_arg_locs (MemLocSet.empty, MemLocSet.empty) args
        in
        let last_writes =
          MemLocSet.fold write_v args_locs wl.last_writes
        in
        let ptr_targets =
          MemLocSet.fold
            (call_arg_ptr_target stmt args_locs)
            ptr_args_locs wl.ptr_targets
        in
        { last_writes; ptr_targets }
      | Guard (exp, _, _) when Info.include_guards ->
        let locs = guarded_locs exp in
        let last_writes = MemLocSet.fold write_v locs wl.last_writes in
        { last_writes; ptr_targets = wl.ptr_targets }
      | _ -> wl
    in
    Some wl
end
