(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)


open Eva_automata

module LocSet = Basic_locations.Set

let get_writes_at_v junct_v (last_writes, _) =
  let check_and_add_var loc v acc =
    if v == junct_v then LocSet.add loc acc
    else acc
  in
  Basic_analysis.VtLocMap.fold check_and_add_var last_writes LocSet.empty

let get_merge_edges (automaton : automaton) junct_v states accesses dist_limit =
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
  Vertex.Hashtbl.add followed_locs junct_v states;
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
        let acc = Edge.Hashtbl.find accesses e in
        let has_read_access = function
          | Basic_access.Reads ml -> LocSet.mem ml fl
          | _ -> false
        in
        let has_read = List.exists has_read_access acc in
        let apply_write_access fl = function
          | Basic_access.Writes_to (ml, join) ->
            if has_read then LocSet.add ml fl
            else if not join then LocSet.remove ml fl
            else fl
          | _ -> fl
        in
        let fl = List.fold_left apply_write_access fl acc in
        let update_succ_fl fl =
          match Vertex.Hashtbl.find_opt followed_locs succ with
          | Some prec_fl ->
            let fl = LocSet.union prec_fl fl in
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

  if vertices_with_read = [] then []
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

type options = {
  enabled: bool;
  dist_limit: int;
  interproc: bool;
  include_guards: bool;
  required_writes: int;
}

type preliminary_info = {
  automaton: automaton;
  options: options;
  states: Basic_analysis.lw_and_pt Vertex.Hashtbl.t;
  accesses: Basic_access.mem_access list Edge.Hashtbl.t;
}

module EdgeKeyTbl = Datatype.Int.Hashtbl

let add_merge_edge tbl k e =
  match e.edge_transition with
  | Return _ -> ()
  (* Do not merge after a return, so that interprocedural partitioning
     works *)
  | _ -> EdgeKeyTbl.add tbl e.edge_key k

let get_junction_partitioning { automaton; options; states; accesses } =
  let split_v = Vertex.Hashtbl.create 4
  and merge_e = EdgeKeyTbl.create 4 in
  let check_and_add_junct_v v wl =
    if G.in_degree automaton.graph v > 1 then begin
      let wl = get_writes_at_v v wl in
      if LocSet.cardinal wl >= options.required_writes then begin
        let edges_of_merge =
          get_merge_edges automaton v wl accesses options.dist_limit
        in
        if edges_of_merge <> [] then begin
          Vertex.Hashtbl.add split_v v ();
          List.iter (add_merge_edge merge_e v) edges_of_merge;
        end;
      end;
    end;
  in
  Vertex.Hashtbl.iter check_and_add_junct_v states;
  split_v, merge_e

let get_call_partitioning { automaton; options; states; accesses } =
  let call_merge_e = EdgeKeyTbl.create 4 in
  let add_call_merges (_, e, v) =
    match e.edge_transition with
    | Call (_, lhost, _, stmt) when not (Eva_ast.is_no_effect_frama_c_builtin lhost) ->
      let wl = get_writes_at_v v (Vertex.Hashtbl.find states v) in
      let edges_of_merge =
        get_merge_edges automaton v wl accesses options.dist_limit
      in
      if edges_of_merge = [] then
        EdgeKeyTbl.add call_merge_e e.edge_key stmt
      else
        List.iter (add_merge_edge call_merge_e stmt) edges_of_merge;
    | _ -> ()
  in
  G.iter_edges_e add_call_merges automaton.graph;
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
      Basic_access.get_edge_accesses automaton interproc_args states
    in
    let info = { automaton; options; states; accesses } in
    let split_v, merge_e = get_junction_partitioning info
    and call_merge_e = get_call_partitioning info in
    { split_v; merge_e; call_merge_e }
  end else
    {
      split_v = Vertex.Hashtbl.create 0;
      merge_e = EdgeKeyTbl.create 0;
      call_merge_e = EdgeKeyTbl.create 0;
    }
