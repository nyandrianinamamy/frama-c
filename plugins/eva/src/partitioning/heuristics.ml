(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

let is_internal_function lhost =
  match lhost with
  | Eva_ast.Var vi ->
    Ast_info.start_with_frama_c_builtin vi.vorig_name
  | _ -> false

module MemLoc =
struct
  type t =
    | Var of Eva_ast.varinfo
    | HeapBlk of int (* block on the heap: the integer is the statement id *)
    | OtherPtrTarget

  let compare ml1 ml2 =
    match ml1, ml2 with
    | Var vi1, Var vi2 -> Cil_datatype.Varinfo.compare vi1 vi2
    | _, _ -> compare ml1 ml2
end

module MemLocMap = Map.Make (MemLoc)
module MemLocSet = Set.Make (MemLoc)

module WrittenLocs =
struct
  type t = {
    last_writes: vertex MemLocMap.t;
    ptr_targets: MemLocSet.t MemLocMap.t;
  }

  let initial =
    { last_writes = MemLocMap.empty; ptr_targets = MemLocMap.empty }

  let join v wl1 wl2 =
    let merge_writes _ v1 v2 =
      match v1, v2 with
      | Some v1, Some v2 when v1 == v2 -> Some v1
      | _ -> Some v
    in
    let merge_targets _ ml1 ml2 = Some (MemLocSet.union ml1 ml2) in
    let last_writes =
      MemLocMap.merge merge_writes wl1.last_writes wl2.last_writes
    in
    let ptr_targets =
      MemLocMap.union merge_targets wl1.ptr_targets wl2.ptr_targets
    in
    { last_writes; ptr_targets }

  let widen wl1 wl2 =
    let included ml targets =
      match MemLocMap.find_opt ml wl1.ptr_targets with
      | None -> false
      | Some prev_targets -> MemLocSet.subset targets prev_targets
    in
    if MemLocMap.for_all included wl2.ptr_targets then Fixpoint
    else Widening wl2

  let transfer (_, e, v) wl =
    let open Eva_ast_types in

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
      match MemLocMap.find_opt ml wl.ptr_targets with
      | Some mls -> mls
      | None -> MemLocSet.singleton MemLoc.OtherPtrTarget
    and locs_of_init = function
      | SingleInit (exp, _) -> locs_of_exp exp
      | CompoundInit (_, init_l) ->
        List.fold_left
          (fun acc (_, init) -> MemLocSet.union acc (locs_of_init init))
          MemLocSet.empty init_l
    in

    let rec recursive_locs locs =
      let add_targets loc acc =
        match MemLocMap.find_opt loc wl.ptr_targets with
        | None -> acc
        | Some mls -> MemLocSet.union mls acc
      in
      let new_locs = MemLocSet.fold add_targets locs MemLocSet.empty in
      let new_locs = MemLocSet.diff new_locs locs in
      if MemLocSet.is_empty new_locs then
        locs
      else
        MemLocSet.union
          (MemLocSet.union locs new_locs) (recursive_locs new_locs)
    in
    let add_arg_locs (target_locs, ptr_locs) arg =
      match arg.typ.tnode with
      | TPtr typ ->
        let locs = locs_of_exp arg |> recursive_locs in
        let ptr_locs =
          match typ.tnode with
          | TPtr _ -> MemLocSet.union locs ptr_locs
          | _ -> ptr_locs
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
          match MemLocMap.find_opt ml wl.ptr_targets with
          | None -> target_locs
          | Some mls -> MemLocSet.union mls target_locs
      in
      let target_locs =
        match alloc_stmt with
        | None -> target_locs
        | Some stmt ->
          MemLocSet.add (MemLoc.HeapBlk stmt.Cil_types.sid) target_locs
      in
      MemLocMap.add ml target_locs pt
    in
    let call_arg_ptr_target stmt target_locs ml pt =
      assign_ptr_target ~alloc_stmt:stmt true target_locs ml pt
    in

    let write_v ml = MemLocMap.add ml v in

    let wl = match e.edge_transition with
      | Assign (lval, exp, _) ->
        let locs = locs_of_lval lval in
        let last_writes = MemLocSet.fold write_v locs wl.last_writes in
        let ptr_targets =
          match lval.typ.tnode with
          | TPtr _ ->
            let target_locs = locs_of_exp exp in
            let lval_is_compound =
              match snd lval.node with NoOffset -> false | _ -> true
            in
            MemLocSet.fold
              (assign_ptr_target lval_is_compound target_locs)
              locs wl.ptr_targets
          | _ -> wl.ptr_targets
        in
        { last_writes; ptr_targets }
      | Init (vi, init, _) ->
        let last_writes = MemLocMap.add (MemLoc.Var vi) v wl.last_writes in
        let ptr_targets =
          match vi.vtype.tnode with
          | TPtr _ ->
            MemLocMap.add (MemLoc.Var vi) (locs_of_init init) wl.ptr_targets
          | _ -> wl.ptr_targets
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
          match lval.typ.tnode with
          | TPtr _ ->
            let lval_is_compound =
              match snd lval.node with NoOffset -> false | _ -> true
            in
            MemLocSet.fold
              (assign_ptr_target ~alloc_stmt:stmt lval_is_compound args_locs)
              locs wl.ptr_targets
          | _ -> wl.ptr_targets
        in
        let ptr_targets =
          MemLocSet.fold
            (call_arg_ptr_target stmt args_locs)
            ptr_args_locs ptr_targets
        in
        { last_writes; ptr_targets }
      | Call (None, exp, args, stmt) when not (is_internal_function exp) ->
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
      | _ -> wl
    in
    Some wl
end

module WriteFwAnalysis = ForwardAnalysis (WrittenLocs)

type trans_effect =
  | Reads_var of Eva_ast.varinfo
  | Reads_pointed
  | Writes_to_var of Eva_ast.varinfo
  | Writes_to_compound of Eva_ast.varinfo
  | Writes_to_pointed

let get_trans_effects automaton return_pointers =
  let e_effects = Edge.Hashtbl.create 4
  and stacked = Vertex.Hashtbl.create 4 in
  Vertex.Hashtbl.add stacked automaton.entry_point ();
  let rec add_effects = function
    | [] -> ()
    | v :: v_stack ->
      let register_effects (_, e, _) =
        let open Eva_ast_types in
        let rec offset_effects = function
          | NoOffset -> []
          | Field (_, offset) -> offset_effects offset
          | Index (exp, offset) -> exp_effects exp @ offset_effects offset
        and lval_effects { node = lhost, offset } =
          (match lhost with
           | Var vi -> [if vi.vaddrof then Reads_pointed else Reads_var vi]
           | Mem exp -> Reads_pointed :: exp_effects exp) @
          offset_effects offset
        and written_lval_effects { node = lhost, offset } =
          (match lhost, offset with
           | Var vi, _ when vi.vaddrof -> [Writes_to_pointed]
           | Var vi, NoOffset -> [Writes_to_var vi]
           | Var vi, _ -> [Writes_to_compound vi]
           | Mem exp, _ -> Writes_to_pointed :: exp_effects exp) @
          offset_effects offset
        and exp_effects { node } =
          match node with
          | Lval lval | AddrOf lval | StartOf lval -> lval_effects lval
          | UnOp (_, exp, _) | CastE (_, exp) -> exp_effects exp
          | BinOp (_, exp1, exp2, _) -> exp_effects exp1 @ exp_effects exp2
          | _ -> []
        and arg_effects exp =
          (match exp.node with
           | Lval { typ = { tnode = TPtr _ } } ->
             [Reads_pointed; Writes_to_pointed]
           | _ -> []) @
          exp_effects exp
        and init_effects = function
          | SingleInit (exp, _) -> exp_effects exp
          | CompoundInit (_, init_l) ->
            List.concat_map (fun (_, init) -> init_effects init) init_l
        in
        let effects = match e.edge_transition with
          | Return (exp, _) when return_pointers ->
            Reads_pointed ::
            (match exp with None -> [] | Some exp -> exp_effects exp)
          | Return (Some exp, _) -> exp_effects exp
          | Guard (exp, _, _) -> exp_effects exp
          | Assign (lval, exp, _) -> written_lval_effects lval @ exp_effects exp
          | Call (lval, lhost, args, _) when not (is_internal_function lhost) ->
            let exp = Eva_ast.(mk_lval (lhost, NoOffset) |> Build.lval) in
            (match lval with
             | None -> []
             | Some lval -> written_lval_effects lval) @
            arg_effects exp @ List.concat_map exp_effects args
          | Init (vi, init, _) ->
            Writes_to_var vi :: init_effects init
          | _ -> []
        in
        Edge.Hashtbl.add e_effects e effects;
      in
      G.iter_succ_e register_effects automaton.graph v;
      let add_not_stacked v v_stack =
        if Vertex.Hashtbl.mem stacked v then
          v_stack
        else begin
          Vertex.Hashtbl.add stacked v ();
          v :: v_stack
        end
      in
      let v_stack = G.fold_succ add_not_stacked automaton.graph v v_stack in
      add_effects v_stack
  in
  add_effects [automaton.entry_point];
  e_effects

let get_writes_at_v junct_v (wl : WrittenLocs.t) =
  let check_and_add_var loc v lw =
    if v == junct_v then MemLocSet.add loc lw
    else lw
  in
  MemLocMap.fold check_and_add_var wl.last_writes MemLocSet.empty

let get_merge_edges (automaton : automaton) junct_v wl e_effects dist_limit =
  let add_to_stack_of_dist v v_stack v_stack_next_dist must_stack =
    if not must_stack then
      v_stack, v_stack_next_dist
    else if G.in_degree automaton.graph v > 1 then
      v_stack, v :: v_stack_next_dist
    else
      v :: v_stack, v_stack_next_dist
  in

  (* Descend the graph to determine vertices after which partitioning should
     persist: because one of the followed variables is read. More or less
     variables may be tracked because of assignments, this is why we have a
     table of followed variables at each vertex. *)
  let followed_locs = Vertex.Hashtbl.create 4 in
  Vertex.Hashtbl.add followed_locs junct_v wl;
  let rec vertices_with_read v_stack v_stack_next_dist dist =
    match v_stack with
    | [] ->
      if v_stack_next_dist <> [] && dist + 1 < dist_limit
      then vertices_with_read v_stack_next_dist [] (dist + 1)
      else []
    | { vertex_info = LoopHead _ } :: v_stack ->
      (* Do not go through loop heads *)
      vertices_with_read v_stack v_stack_next_dist dist
    | v :: v_stack ->
      let fl = Vertex.Hashtbl.find followed_locs v in
      let process_edge (_, e, succ) (result, v_stack, v_stack_next_dist) =
        let effects = Edge.Hashtbl.find e_effects e in
        let rec has_read_effect = function
          | [] -> false
          | eff :: effects ->
            let has_read = match eff with
              | Reads_var vi -> MemLocSet.mem (MemLoc.Var vi) fl
              | Reads_pointed -> MemLocSet.mem MemLoc.OtherPtrTarget fl
              | _ -> false
            in
            has_read || has_read_effect effects
        in
        let has_read = has_read_effect effects in
        let apply_write_effect fl = function
          | Writes_to_var vi ->
            if has_read then MemLocSet.add (MemLoc.Var vi) fl
            else MemLocSet.remove (MemLoc.Var vi) fl
          | Writes_to_compound vi when has_read ->
            MemLocSet.add (MemLoc.Var vi) fl
          | Writes_to_pointed when has_read -> MemLocSet.add MemLoc.OtherPtrTarget fl
          | _ -> fl
        in
        let fl = List.fold_left apply_write_effect fl effects in
        let update_succ_fl fl =
          match Vertex.Hashtbl.find_opt followed_locs succ with
          | Some prec_fl ->
            let fl = MemLocSet.union prec_fl fl in
            Vertex.Hashtbl.replace followed_locs succ fl;
          | None -> Vertex.Hashtbl.add followed_locs succ fl;
        in
        let result = if has_read then v :: result else result in
        let v_stack, v_stack_next_dist =
          let must_stack = not (Vertex.Hashtbl.mem followed_locs succ) in
          add_to_stack_of_dist succ v_stack v_stack_next_dist must_stack
        in
        update_succ_fl fl;
        result, v_stack, v_stack_next_dist
      in
      let result, v_stack, v_stack_next_dist =
        G.fold_succ_e process_edge automaton.graph v
          ([], v_stack, v_stack_next_dist)
      in
      result @ vertices_with_read v_stack v_stack_next_dist dist
  in
  let vertices_with_read = vertices_with_read [junct_v] [] 0 in

  if vertices_with_read = [] then
    []
  else begin
    (* Go back up in the graph to mark all edges after which the partition
       should persist *)
    let edges_keeping_partition = Edge.Hashtbl.create 4 in
    let stacked = Vertex.Hashtbl.create 4 in
    List.iter (fun e -> Vertex.Hashtbl.add stacked e ()) vertices_with_read;
    let rec add_edges_keeping_partition v_stack v_stack_next_dist dist =
      match v_stack with
      | [] ->
        if v_stack_next_dist <> [] && dist + 1 < dist_limit then
          add_edges_keeping_partition v_stack_next_dist [] (dist + 1);
      | v :: v_stack ->
        let process_edge (pred, e, _) (v_stack, v_stack_next_dist) =
          Edge.Hashtbl.add edges_keeping_partition e ();
          let must_stack =
            not (Vertex.Hashtbl.mem stacked pred) &&
            (match pred.vertex_info with LoopHead _ -> false | _ -> true)
          in
          Vertex.Hashtbl.replace stacked pred ();
          add_to_stack_of_dist pred v_stack v_stack_next_dist must_stack
        in
        let v_stack, v_stack_next_dist =
          G.fold_pred_e process_edge automaton.graph v
            (v_stack, v_stack_next_dist)
        in
        add_edges_keeping_partition v_stack v_stack_next_dist dist;
    in
    add_edges_keeping_partition vertices_with_read [] 0;

    (* Descend the graph again to mark all edges after which the merging should
       occur *)
    let stacked = Vertex.Hashtbl.create 4 in
    Vertex.Hashtbl.add stacked junct_v ();
    let rec edges_of_merge v_stack =
      match v_stack with
      | [] -> []
      | v :: v_stack ->
        let process_edge (_, e, succ) (result, v_stack) =
          if Edge.Hashtbl.mem edges_keeping_partition e then
            if Vertex.Hashtbl.mem stacked succ then
              result, v_stack
            else begin
              Vertex.Hashtbl.add stacked succ ();
              result, succ :: v_stack
            end
          else
            e :: result, v_stack
        in
        let result, v_stack =
          G.fold_succ_e process_edge automaton.graph v ([], v_stack)
        in
        result @ edges_of_merge v_stack
    in
    edges_of_merge [junct_v]
  end

let get_call_writes lval args =
  let open Eva_ast_types in
  let wl =
    match lval with
    | Some { node = Var vi, _ } -> MemLocSet.singleton (MemLoc.Var vi)
    | Some { node = Mem _, _ } -> MemLocSet.singleton MemLoc.OtherPtrTarget
    | None -> MemLocSet.empty
  in
  let add_arg_write wl arg =
    match arg.node with
    | AddrOf { node = Var vi, _ } | StartOf { node = Var vi, _ }
      when vi.vaddrof ->
      MemLocSet.add MemLoc.OtherPtrTarget wl
    | AddrOf { node = Var vi, _ } | StartOf { node = Var vi, _ } ->
      MemLocSet.add (MemLoc.Var vi) wl
    | Lval { typ = { tnode = TPtr _ } } | AddrOf _ | StartOf _ ->
      MemLocSet.add MemLoc.OtherPtrTarget wl
    | _ -> wl
  in
  List.fold_left add_arg_write wl args

type mode =
  | Disabled
  | Intraprocedural
  | Interprocedural

type info = {
  split_v : unit Vertex.Hashtbl.t;
  merge_e : vertex Datatype.Int.Hashtbl.t;
  call_merge_e : Cil_types.stmt Datatype.Int.Hashtbl.t;
}

let get_info mode kf dist_limit =
  if mode <> Disabled then begin
    let automaton = get_automaton kf in
    let writes = WriteFwAnalysis.fixpoint automaton WrittenLocs.initial
    and e_effects = get_trans_effects automaton (mode = Interprocedural) in
    let split_v = Vertex.Hashtbl.create 4
    and merge_e = Datatype.Int.Hashtbl.create 4
    and call_merge_e = Datatype.Int.Hashtbl.create 4 in
    let add_merge_edge tbl k e =
      match e.edge_transition with
      | Return _ -> ()
      | _ -> Datatype.Int.Hashtbl.add tbl e.edge_key k;
    in
    let check_and_add_junct_v v wl =
      if G.in_degree automaton.graph v > 1 then begin
        let wl = get_writes_at_v v wl in
        let edges_of_merge =
          get_merge_edges automaton v wl e_effects dist_limit
        in
        if edges_of_merge <> [] then begin
          Vertex.Hashtbl.add split_v v ();
          List.iter (add_merge_edge merge_e v) edges_of_merge;
        end;
      end;
    in
    let add_call_merges (_, e, v) =
      match e.edge_transition with
      | Call (lval, exp, args, stmt) when not (is_internal_function exp) ->
        let wl = get_call_writes lval args in
        let edges_of_merge =
          get_merge_edges automaton v wl e_effects dist_limit
        in
        if edges_of_merge = [] then
          Datatype.Int.Hashtbl.add call_merge_e e.edge_key stmt
        else
          List.iter (add_merge_edge call_merge_e stmt) edges_of_merge;
      | _ -> ()
    in
    Vertex.Hashtbl.iter check_and_add_junct_v writes;
    G.iter_edges_e add_call_merges automaton.graph;
    { split_v; merge_e; call_merge_e }
  end else
    {
      split_v = Vertex.Hashtbl.create 0;
      merge_e = Datatype.Int.Hashtbl.create 0;
      call_merge_e = Datatype.Int.Hashtbl.create 0;
    }
