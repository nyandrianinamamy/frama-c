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
    | PtrTarget

  let compare = compare
end

module MemLocMap = Map.Make (MemLoc)
module ViSet = Cil_datatype.Varinfo.Hptset

module WrittenLocs =
struct
  type t = {
    last_writes : vertex MemLocMap.t;
    ptr_targets : ViSet.t;
  }

  let initial = { last_writes = MemLocMap.empty; ptr_targets = ViSet.empty }

  let join v wl1 wl2 =
    let ptr_targets = ViSet.union wl1.ptr_targets wl2.ptr_targets in
    let merge_writes loc v1 v2 =
      let v1eqv2 = match v1, v2 with
        | None, None -> true
        | Some v1, Some v2 -> v1 == v2
        | _ -> false
      in
      match loc with
      | MemLoc.PtrTarget ->
        if not v1eqv2 || wl1.ptr_targets != wl2.ptr_targets then Some v
        else v1
      | MemLoc.Var vi ->
        if v1eqv2 then v1
        else if ViSet.mem vi ptr_targets then None
        else Some v
    in
    let last_writes =
      MemLocMap.merge merge_writes wl1.last_writes wl2.last_writes
    in
    { last_writes; ptr_targets }

  let widen _ _ = Fixpoint

  let transfer (_, e, v) wl =
    let open Eva_ast_types in
    let lval_ptr_targets { node = lhost, _ } =
      match lhost with
      | Var vi when vi.vaddrof -> ViSet.singleton vi
      | _ -> ViSet.empty
    in
    let rec exp_ptr_targets exp =
      match exp.node with
      | Lval lval -> lval_ptr_targets lval
      | UnOp (_, exp, _) | CastE (_, exp) -> exp_ptr_targets exp
      | BinOp (_, exp1, exp2, _) ->
        ViSet.union (exp_ptr_targets exp1) (exp_ptr_targets exp2)
      | AddrOf { node = Var vi, _ } | StartOf { node = Var vi, _ } ->
        ViSet.singleton vi
      | _ -> ViSet.empty
    in
    let loc_of_vi vi ptr_targets =
      if ViSet.mem vi ptr_targets then MemLoc.PtrTarget
      else MemLoc.Var vi
    in
    let loc_of_lval lval ptr_targets =
      match fst lval.node with
      | Var vi -> loc_of_vi vi ptr_targets
      | _ -> MemLoc.PtrTarget
    in
    let add_exp_targets last_w exp = ViSet.union last_w (exp_ptr_targets exp) in
    let remove_memloc_vars = ViSet.fold (fun vi -> MemLocMap.remove (Var vi)) in
    let exp_is_ref exp =
      match exp.typ.tnode with
      | TPtr _ | TArray _ -> true
      | _ -> false
    in

    match e.edge_transition with
    | Assign (lval, exp, _) ->
      let new_ptr_targets =
        ViSet.union (lval_ptr_targets lval) (exp_ptr_targets exp)
      in
      let ptr_targets = ViSet.union new_ptr_targets wl.ptr_targets in
      let loc = loc_of_lval lval ptr_targets in
      let last_writes =
        wl.last_writes
        |> remove_memloc_vars new_ptr_targets
        |> MemLocMap.add loc v
      in
      Some { last_writes; ptr_targets }
    | Init (vi, init, _) ->
      let new_ptr_targets =
        let rec parse_init ptr_targets = function
          | SingleInit (exp, _) ->
            add_exp_targets ptr_targets exp
          | CompoundInit (_, init_l) ->
            List.fold_left
              (fun acc (_, init) -> parse_init acc init)
              ptr_targets
              init_l
        in
        parse_init ViSet.empty init
      in
      let ptr_targets = ViSet.union new_ptr_targets wl.ptr_targets in
      let loc = loc_of_vi vi ptr_targets in
      let last_writes =
        wl.last_writes
        |> remove_memloc_vars new_ptr_targets
        |> MemLocMap.add loc v
      in
      Some { last_writes; ptr_targets }
    | Call (None, exp, args, _) when not (is_internal_function exp) ->
      let new_ptr_targets = List.fold_left add_exp_targets ViSet.empty args in
      let ptr_targets = ViSet.union new_ptr_targets wl.ptr_targets in
      let last_writes = remove_memloc_vars new_ptr_targets wl.last_writes in
      let last_writes =
        if List.exists exp_is_ref args
        then MemLocMap.add MemLoc.PtrTarget v last_writes
        else last_writes
      in
      Some { last_writes; ptr_targets }
    | Call (Some lval, _, args, _) ->
      let new_ptr_targets =
        List.fold_left add_exp_targets (lval_ptr_targets lval) args
      in
      let ptr_targets = ViSet.union new_ptr_targets wl.ptr_targets in
      let loc = loc_of_lval lval ptr_targets in
      let last_writes =
        wl.last_writes
        |> remove_memloc_vars new_ptr_targets
        |> MemLocMap.add loc v
      in
      let last_writes =
        if List.exists exp_is_ref args
        then MemLocMap.add MemLoc.PtrTarget v last_writes
        else last_writes
      in
      Some { last_writes; ptr_targets }
    | _ -> Some wl
end

module WriteFwAnalysis = ForwardAnalysis (WrittenLocs)

type trans_effect =
  | Reads_var of Eva_ast.varinfo
  | Reads_pointed
  | Writes_to_var of Eva_ast.varinfo
  | Writes_to_array of Eva_ast.varinfo
  | Writes_to_pointed
  | Points_to of Eva_ast.varinfo

let get_trans_effects automaton =
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
           | Var vi -> [Reads_var vi]
           | Mem exp -> Reads_pointed :: exp_effects exp) @
          offset_effects offset
        and written_lval_effects { node = lhost, offset } =
          (match lhost, offset with
           | Var vi, NoOffset -> [Writes_to_var vi]
           | Var vi, _ -> [Writes_to_array vi]
           | Mem exp, _ -> Writes_to_pointed :: exp_effects exp) @
          offset_effects offset
        and exp_effects { node } =
          match node with
          | AddrOf ({ node = Var vi, _ } as lval)
          | StartOf ({ node = Var vi, _ } as lval) ->
            Points_to vi :: lval_effects lval
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
          | Return (Some exp, _) -> Reads_pointed :: exp_effects exp
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

let get_writes_at_v junct_v (writes : WrittenLocs.t) =
  let check_and_add_var loc v (wvars, pt_written) =
    if v == junct_v then
      match loc with
      | MemLoc.Var vi -> ViSet.add vi wvars, pt_written
      | MemLoc.PtrTarget ->
        ViSet.union writes.ptr_targets wvars, true
    else
      wvars, pt_written
  in
  MemLocMap.fold check_and_add_var writes.last_writes (ViSet.empty, false)

let get_merge_edges (automaton : automaton) junct_v writes e_effects
    dist_limit =
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
  let followed_vars = Vertex.Hashtbl.create 4 in
  Vertex.Hashtbl.add followed_vars junct_v writes;
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
      let wvars, pt_written = Vertex.Hashtbl.find followed_vars v in
      let process_edge (_, e, succ) (result, v_stack, v_stack_next_dist) =
        let effects = Edge.Hashtbl.find e_effects e in
        let rec has_read_effect = function
          | [] -> false
          | eff :: effects ->
            let has_read = match eff with
              | Reads_var vi -> ViSet.mem vi wvars
              | Reads_pointed -> pt_written
              | _ -> false
            in
            has_read || has_read_effect effects
        in
        let has_read = has_read_effect effects in
        let apply_write_effect (wvars, pt_written) = function
          | Writes_to_var vi ->
            if has_read then ViSet.add vi wvars, pt_written
            else ViSet.remove vi wvars, pt_written
          | Writes_to_array vi when has_read ->
            ViSet.add vi wvars, pt_written
          | Writes_to_pointed when has_read -> wvars, true
          | Points_to vi when ViSet.mem vi wvars -> wvars, true
          | _ -> wvars, pt_written
        in
        let fvars =
          List.fold_left apply_write_effect (wvars, pt_written) effects
        in
        let update_succ_fvars fvars =
          let fvars_union (wvars1, pt_written1) (wvars2, pt_written2) =
            ViSet.union wvars1 wvars2, pt_written1 || pt_written2
          in
          match Vertex.Hashtbl.find_opt followed_vars succ with
          | Some prec_fvars ->
            let fvars = fvars_union prec_fvars fvars in
            Vertex.Hashtbl.replace followed_vars succ fvars;
          | None -> Vertex.Hashtbl.add followed_vars succ fvars;
        in
        let result = if has_read then v :: result else result in
        let v_stack, v_stack_next_dist =
          let must_stack = not (Vertex.Hashtbl.mem followed_vars succ) in
          add_to_stack_of_dist succ v_stack v_stack_next_dist must_stack
        in
        update_succ_fvars fvars;
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
  let wvars, pt_written =
    match lval with
    | Some { node = Var vi, _ } -> ViSet.singleton vi, false
    | Some { node = Mem _, _ } -> ViSet.empty, true
    | None -> ViSet.empty, false
  in
  let add_arg_write (wvars, pt_written) arg =
    match arg.node with
    | Lval { typ = { tnode = TPtr _ } } -> wvars, true
    | AddrOf { node = Var vi, _ } | StartOf { node = Var vi, _ } ->
      ViSet.add vi wvars, pt_written
    | AddrOf _ | StartOf _ -> wvars, true
    | _ -> wvars, pt_written
  in
  List.fold_left add_arg_write (wvars, pt_written) args

type info = {
  split_v : unit Vertex.Hashtbl.t;
  merge_e : vertex Datatype.Int.Hashtbl.t;
  call_merge_e : Cil_types.stmt Datatype.Int.Hashtbl.t;
}

let get_info enabled kf dist_limit =
  if enabled then begin
    let automaton = get_automaton kf in
    let writes = WriteFwAnalysis.fixpoint automaton WrittenLocs.initial
    and e_effects = get_trans_effects automaton in
    let split_v = Vertex.Hashtbl.create 4
    and merge_e = Datatype.Int.Hashtbl.create 4
    and call_merge_e = Datatype.Int.Hashtbl.create 4 in
    let add_merge_edge tbl k e =
      match e.edge_transition with
      | Return _ -> ()
      | _ -> Datatype.Int.Hashtbl.add tbl e.edge_key k;
    in
    let check_and_add_junct_v v writes =
      if G.in_degree automaton.graph v > 1 then begin
        let writes = get_writes_at_v v writes in
        let edges_of_merge =
          get_merge_edges automaton v writes e_effects dist_limit
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
        let writes = get_call_writes lval args in
        let edges_of_merge =
          get_merge_edges automaton v writes e_effects dist_limit
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
