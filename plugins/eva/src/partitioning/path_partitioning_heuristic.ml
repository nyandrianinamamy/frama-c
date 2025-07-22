(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)


open Eva_automata

module LocSet = Basic_locations.Set

type options = {
  enabled: bool;
  dist_limit: int;
  interproc: bool;
  include_guards: bool;
  required_writes: int;
}

type exploration_info = {
  automaton: automaton;
  options: options;
  accesses: Basic_access.mem_access list Edge.Hashtbl.t;
}

(* Get the memory locations whose last write is set to be at the given
   junct_v. *)
let get_writes_at_v junct_v (last_writes, _) =
  let check_and_add_var loc v acc =
    if v == junct_v then LocSet.add loc acc
    else acc
  in
  Basic_analysis.VtLocMap.fold check_and_add_var last_writes LocSet.empty

(* Tell if a memory access reads one of the followed locations. *)
let reads_foll_loc foll_locs = function
  | Basic_access.Reads ml -> LocSet.mem ml foll_locs
  | _ -> false

(* Update the followed locations if the given access is a write. *)
and apply_write_access has_read foll_locs = function
  | Basic_access.Writes_to (ml, partial) ->
    if has_read then LocSet.add ml foll_locs
    else if not partial then LocSet.remove ml foll_locs
    else foll_locs
  | _ -> foll_locs

(* Update the followed locations of succ_v in followed_locs_map by taking
   new_fl into account. *)
let update_succ_foll_locs followed_locs_map succ_v new_fl =
  match Vertex.Hashtbl.find_opt followed_locs_map succ_v with
  | Some prec_fl ->
    let fl = LocSet.union prec_fl new_fl in
    Vertex.Hashtbl.replace followed_locs_map succ_v fl;
  | None -> Vertex.Hashtbl.add followed_locs_map succ_v new_fl

(* Check whether v is in a loop which does not include its predecessor pred. If
   so, add incoming edges of v which are in the loop in the set
   edges_closing_loops. *)
let check_nested_loop automaton pred v edges_closing_loops =
  match find_loop automaton v with
  | None -> ()
  | Some { wto } ->
    let loop_v = Wto.flatten wto in
    if not (List.memq pred loop_v) then
      let add_if_included (other_pred, e, _) =
        if other_pred != pred && List.memq other_pred loop_v then
          Edge.Hashtbl.add edges_closing_loops e ();
      in
      G.iter_pred_e add_if_included automaton.graph v

(* Descend the graph from start_v, up to info.options.dist_limit junction
   points, and tell where followed variables are read among the visited edges.
   At start_v, the followed variables are the given written_locs, but according
   to the writes into info.accesses, they may be different at the following
   vertices. It also computes looping bounds, i.e. edges that come back to an
   already visited vertex after traversing the head of the loop containing
   start_v. *)
let find_vertices_with_read start_v written_locs info =
  let followed_locs = Vertex.Hashtbl.create 4
  (* Edges closing loops are not looping bounds, they are the end of nested
     loops *)
  and edges_closing_loops = Edge.Hashtbl.create 4
  and looping_bounds = Edge.Hashtbl.create 4 in
  Vertex.Hashtbl.add followed_locs start_v written_locs;
  (* The graph is visited by maintaining two stacks: the stack of the current
     distance and the stack of the next distance. When the first stack is empty,
     we switch to the next distance. The distance increases as we cross junction
     points. *)
  let rec aux v_stack v_stack_next_dist dist =
    match v_stack with
    | [] ->
      if v_stack_next_dist <> [] && dist + 1 < info.options.dist_limit
      then aux v_stack_next_dist [] (dist + 1)
      else []
    | (v, crossed) :: v_stack ->
      let fl = Vertex.Hashtbl.find followed_locs v in
      let process_edge (_, e, succ) (result, v_stack, v_stack_next_dist) =
        let succ_stacked = Vertex.Hashtbl.mem followed_locs succ in
        if succ_stacked && Vertex.Set.mem succ crossed then begin
          if not (Edge.Hashtbl.mem edges_closing_loops e) then
            Edge.Hashtbl.add looping_bounds e ();
          result, v_stack, v_stack_next_dist
        end else begin
          let acc = Edge.Hashtbl.find info.accesses e in
          let has_read = List.exists (reads_foll_loc fl) acc in
          let fl = List.fold_left (apply_write_access has_read) fl acc in
          let result = if has_read then v :: result else result in
          (* The successor may have already been visited, making this update
             useless, unfortunately *)
          update_succ_foll_locs followed_locs succ fl;
          let v_stack, v_stack_next_dist =
            if succ_stacked then
              v_stack, v_stack_next_dist
            else if G.in_degree info.automaton.graph succ > 1 then begin
              check_nested_loop info.automaton v succ edges_closing_loops;
              let crossed = Vertex.Set.add succ crossed in
              v_stack, (succ, crossed) :: v_stack_next_dist
            end else
              (succ, crossed) :: v_stack, v_stack_next_dist
          in
          result, v_stack, v_stack_next_dist
        end
      in
      let result, v_stack, v_stack_next_dist =
        G.fold_succ_e process_edge info.automaton.graph v
          ([], v_stack, v_stack_next_dist)
      in
      result @ aux v_stack v_stack_next_dist dist
  in
  aux [start_v, Vertex.Set.singleton start_v] [] 0, looping_bounds

(* Go up in the graph from start_vertices up to dist_limit junction points or a
   looping bound, to mark all visited edges. *)
let mark_preceding_edges graph start_vertices dist_limit looping_bounds =
  let marked_edges = Edge.Hashtbl.create 4 in
  let stacked = Vertex.Hashtbl.create 4 in
  List.iter (fun e -> Vertex.Hashtbl.add stacked e ()) start_vertices;
  let rec aux v_stack v_stack_next_dist dist =
    match v_stack with
    | [] ->
      if v_stack_next_dist <> [] && dist + 1 < dist_limit then
        aux v_stack_next_dist [] (dist + 1);
    | v :: v_stack ->
      let process_edge (pred, e, _) (v_stack, v_stack_next_dist) =
        if Edge.Hashtbl.mem looping_bounds e then
          v_stack, v_stack_next_dist
        else begin
          Edge.Hashtbl.add marked_edges e ();
          let pred_was_stacked = Vertex.Hashtbl.mem stacked pred in
          Vertex.Hashtbl.replace stacked pred ();
          if pred_was_stacked then
            v_stack, v_stack_next_dist
          else if G.in_degree graph pred > 1 then
            v_stack, pred :: v_stack_next_dist
          else
            pred :: v_stack, v_stack_next_dist
        end
      in
      let v_stack, v_stack_next_dist =
        G.fold_pred_e process_edge graph v
          (v_stack, v_stack_next_dist)
      in
      aux v_stack v_stack_next_dist dist;
  in
  aux start_vertices [] 0;
  marked_edges

(* Descend the graph from start_v, stopping when we go out of edges_territory.
   The edges that go out of edges_territory are returned. *)
let find_boundary_edges graph start_v edges_territory =
  let stacked = Vertex.Hashtbl.create 4 in
  Vertex.Hashtbl.add stacked start_v ();
  let rec aux = function
    | [] -> []
    | v :: v_stack ->
      let process_edge (_, e, succ) (result, v_stack) =
        if Edge.Hashtbl.mem edges_territory e then
          if Vertex.Hashtbl.mem stacked succ then
            result, v_stack
          else begin
            Vertex.Hashtbl.add stacked succ ();
            result, succ :: v_stack
          end
        else
          e :: result, v_stack
      in
      let result, v_stack = G.fold_succ_e process_edge graph v ([], v_stack) in
      result @ aux v_stack
  in
  aux [start_v]

(* Get the edges where the partitioning initiated at start_v should be ended.
   If no edge is returned, then no partitioning should be done at start_v. *)
let compute_edges_of_merge start_v written_locs info =
  (* Partitioning should persist until the vertices with read *)
  let vertices_with_read, looping_bounds =
    find_vertices_with_read start_v written_locs info
  in
  (* No vertices with read: no partitioning *)
  if vertices_with_read = [] then []
  else begin
    (* Go back up in the graph to mark the edges on which partitioning should
       persist *)
    let edges_with_partition =
      mark_preceding_edges info.automaton.graph vertices_with_read
        info.options.dist_limit looping_bounds
    in
    (* Use these marks to decide when merging must be done *)
    find_boundary_edges info.automaton.graph start_v edges_with_partition
  end

module EdgeKeyTbl = Datatype.Int.Hashtbl

let add_edge_if_not_return tbl k e =
  match e.edge_transition with
  | Return _ -> ()
  (* Do not merge after a return, so that interprocedural partitioning works *)
  | _ -> EdgeKeyTbl.add tbl e.edge_key k

(* Get the partitioning information concerning junction points. *)
let compute_junction_partitioning states info =
  let split_v = Vertex.Hashtbl.create 4
  and merge_e = EdgeKeyTbl.create 4 in
  let check_and_add_junct_v v states =
    if G.in_degree info.automaton.graph v > 1 then begin
      match v.vertex_info with
      | LoopHead _ -> () (* We never enable partitioning on loop heads *)
      | _ ->
        let written_locs = get_writes_at_v v states
        and req_writes = info.options.required_writes in
        if LocSet.cardinal written_locs >= req_writes then begin
          let edges_of_merge = compute_edges_of_merge v written_locs info in
          if edges_of_merge <> [] then begin
            Vertex.Hashtbl.add split_v v ();
            List.iter (add_edge_if_not_return merge_e v) edges_of_merge;
          end;
        end;
    end;
  in
  Vertex.Hashtbl.iter check_and_add_junct_v states;
  split_v, merge_e

(* Get the partitioning information concerning calls. Note that it is important
   even in non-interprocedural mode, because of builtins and specifications,
   which create branches even if interprocedural mode is disabled. *)
let compute_call_partitioning states info =
  let call_merge_e = EdgeKeyTbl.create 4 in
  let add_call_merges (_, e, v) =
    match e.edge_transition with
    | Call (_, lhost, _, stmt) when not (Eva_ast.is_no_effect_frama_c_builtin lhost) ->
      let state =
        try Vertex.Hashtbl.find states v
        with Not_found ->
          (* I don't know why v could not be found, but it happened once *)
          Basic_analysis.VtLocMap.empty, Basic_locations.SetMap.empty
      in
      let written_locs = get_writes_at_v v state in
      let edges_of_merge = compute_edges_of_merge v written_locs info in
      if edges_of_merge = [] then
        EdgeKeyTbl.add call_merge_e e.edge_key stmt
      else
        List.iter (add_edge_if_not_return call_merge_e stmt) edges_of_merge;
    | _ -> ()
  in
  G.iter_edges_e add_call_merges info.automaton.graph;
  call_merge_e

type result = {
  split_v: unit Vertex.Hashtbl.t;
  merge_e: vertex EdgeKeyTbl.t;
  call_merge_e: Cil_types.stmt EdgeKeyTbl.t;
}

let compute kf options =
  if options.enabled then begin
    let module LwAndPt =
      Basic_analysis.LwAndPt
        (struct let include_guards = options.include_guards end)
    in
    let module WriteFwAnalysis = ForwardAnalysis (LwAndPt) in
    let automaton = get_automaton kf in
    let formals = Kernel_function.get_formals kf in
    let states = WriteFwAnalysis.fixpoint automaton (LwAndPt.initial formals) in
    let accesses =
      let interproc_args = if options.interproc then Some formals else None in
      Basic_access.compute_edge_accesses automaton.graph interproc_args states
    in
    let info = { automaton; options; accesses } in
    let split_v, merge_e = compute_junction_partitioning states info
    and call_merge_e = compute_call_partitioning states info in
    { split_v; merge_e; call_merge_e }
  end else
    {
      split_v = Vertex.Hashtbl.create 0;
      merge_e = EdgeKeyTbl.create 0;
      call_merge_e = EdgeKeyTbl.create 0;
    }
