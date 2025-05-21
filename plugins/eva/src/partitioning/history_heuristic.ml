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
  type elt =
    | Var of Eva_ast.varinfo
    | HeapBlk of Cil_types.stmt (* block on the heap *)
    | OtherPtrTarget

  let initial_values = []
  let dependencies = []

  include Datatype.Make_with_collections
      (struct
        type t = elt
        let name = "Partition.Heuristics.MemLoc"
        let reprs = [OtherPtrTarget]
        let structural_descr = Structural_descr.t_unknown
        let compare ml1 ml2 =
          match ml1, ml2 with
          | Var vi1, Var vi2 -> Cil_datatype.Varinfo.compare vi1 vi2
          | _, _ -> compare ml1 ml2
        let equal ml1 ml2 = compare ml1 ml2 = 0
        let hash = function
          | Var vi -> Hashtbl.hash (1, Cil_datatype.Varinfo.hash vi)
          | HeapBlk stmt -> Hashtbl.hash (2, Cil_datatype.Stmt.hash stmt)
          | OtherPtrTarget -> Hashtbl.hash 3
        let copy = Fun.id
        let rehash = Fun.id
        let mem_project = Datatype.never_any_project
        let pretty fmt = function
          | Var vi -> Cil_datatype.Varinfo.pretty fmt vi
          | HeapBlk stmt ->
            Format.fprintf fmt "[%a]" Cil_datatype.Stmt.pretty stmt
          | OtherPtrTarget -> Format.fprintf fmt "#"
      end)

  let id = function
    | Var vi -> vi.vid
    | HeapBlk stmt -> Int.max_int / 2 + stmt.sid
    | OtherPtrTarget -> Int.max_int
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
    | MemLoc.Var { vglob = true } | MemLoc.OtherPtrTarget ->
      MemLocSet.singleton MemLoc.OtherPtrTarget
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
        let target = MemLocSet.singleton MemLoc.OtherPtrTarget in
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
    let merge_targets _ ml1 ml2 = MemLocSet.union ml1 ml2 in
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
      | Guard (exp, _, _) when Info.include_guards ->
        let locs = guarded_locs exp in
        let last_writes = MemLocSet.fold write_v locs wl.last_writes in
        { last_writes; ptr_targets = wl.ptr_targets }
      | _ -> wl
    in
    Some wl
end

type trans_effect =
  | Reads of MemLoc.t
  | Writes_to of MemLoc.t * bool
  (* the boolean indicates if it's a join write *)

let get_trans_effects automaton interproc_args writes =
  let e_effects = Edge.Hashtbl.create 4 in
  let register_effects (v, e, _) =
    let open Eva_ast_types in

    let ptr_targets =
      match Vertex.Hashtbl.find_opt writes v with
      | None -> MlsMemLocMap.empty
      | Some wl -> wl.ptr_targets
    in
    let open MemLocUtil (struct let ptr_targets = ptr_targets end) in

    let to_reads ml = Reads ml
    and to_writes { node = _, offset } ml =
      let is_compound = match offset with NoOffset -> false | _ -> true in
      Writes_to (ml, is_compound)
    and to_arg_writes ml = Writes_to (ml, true) in
    let locs_to_eff conv locs =
      MemLocSet.fold List.cons locs [] |> List.map conv
    in

    let rec offset_effects = function
      | NoOffset -> []
      | Field (_, offset) -> offset_effects offset
      | Index (exp, offset) -> exp_effects exp @ offset_effects offset
    and lhost_effects = function
      | Var vi -> [Reads (MemLoc.Var vi)]
      | Mem exp -> locs_to_eff to_reads (locs_of_exp exp) @ exp_effects exp
    and lval_effects { node = lhost, offset } =
      lhost_effects lhost @ offset_effects offset
    and written_lval_effects ({ node = lhost, offset } as lval) =
      (match lhost with Mem exp -> exp_effects exp | _ -> []) @
      locs_to_eff (to_writes lval) (locs_of_lval lval) @
      offset_effects offset
    and exp_effects { node } =
      match node with
      | Lval lval | AddrOf lval | StartOf lval -> lval_effects lval
      | UnOp (_, exp, _) | CastE (_, exp) -> exp_effects exp
      | BinOp (_, exp1, exp2, _) -> exp_effects exp1 @ exp_effects exp2
      | _ -> []
    and arg_effects exp =
      let ptr_effects =
        match exp.node with
        | Lval lval when typ_is_ptr lval.typ ->
          let locs = locs_of_nested_lval lval |> recursive_locs in
          locs_to_eff to_reads locs @ locs_to_eff to_arg_writes locs
        | AddrOf lval | StartOf lval when typ_is_ptr lval.typ ->
          let locs = locs_of_lval lval |> recursive_locs in
          locs_to_eff to_reads locs @ locs_to_eff to_arg_writes locs
        | AddrOf lval | StartOf lval ->
          locs_to_eff to_arg_writes (locs_of_lval lval)
        | _ -> []
      in
      ptr_effects @ exp_effects exp
    and init_effects = function
      | SingleInit (exp, _) -> exp_effects exp
      | CompoundInit (_, init_l) ->
        List.concat_map (fun (_, init) -> init_effects init) init_l
    in

    let arg_ret_eff vi =
      if typ_is_ptr vi.Cil_types.vtype then
        locs_of_deref (MemLoc.Var vi)
        |> recursive_locs
        |> locs_to_eff to_reads
      else []
    and ret_ptr_eff exp =
      if typ_is_ptr exp.typ then
        locs_of_exp exp
        |> recursive_locs
        |> locs_to_eff to_reads
      else []
    in

    let effects = match e.edge_transition with
      | Return (None, _) when interproc_args <> None ->
        List.concat_map arg_ret_eff (Option.get interproc_args)
      | Return (Some exp, _) when interproc_args <> None ->
        List.concat_map arg_ret_eff (Option.get interproc_args) @
        ret_ptr_eff exp @ exp_effects exp
      | Return (Some exp, _) -> exp_effects exp
      | Guard (exp, _, _) -> exp_effects exp
      | Assign (lval, exp, _) -> written_lval_effects lval @ exp_effects exp
      | Call (lval, lhost, args, _) when not (is_internal_function lhost) ->
        (match lval with
         | None -> []
         | Some lval -> written_lval_effects lval) @
        lhost_effects lhost @ List.concat_map arg_effects args
      | Init (vi, init, _) ->
        Writes_to (MemLoc.Var vi, false) :: init_effects init
      | _ -> []
    in
    Edge.Hashtbl.add e_effects e effects;
  in
  G.iter_edges_e register_effects (automaton: automaton).graph;
  e_effects

let get_writes_at_v junct_v wl =
  let check_and_add_var loc v lw =
    if v == junct_v then MemLocSet.add loc lw
    else lw
  in
  VMemLocMap.fold check_and_add_var wl.last_writes MemLocSet.empty

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
        let has_read_effect = function
          | Reads ml -> MemLocSet.mem ml fl
          | _ -> false
        in
        let has_read = List.exists has_read_effect effects in
        let apply_write_effect fl = function
          | Writes_to (ml, join) ->
            if has_read then MemLocSet.add ml fl
            else if not join then MemLocSet.remove ml fl
            else fl
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

type options = {
  mode: [ `None | `Normal | `Full ];
  interproc: bool;
}

type info = {
  split_v : unit Vertex.Hashtbl.t;
  merge_e : vertex Datatype.Int.Hashtbl.t;
  call_merge_e : Cil_types.stmt Datatype.Int.Hashtbl.t;
}

let get_info options kf dist_limit =
  if options.mode <> `None then begin
    let module WrittenLocs =
      WrittenLocs (struct let include_guards = options.mode = `Full end)
    in
    let module WriteFwAnalysis = ForwardAnalysis (WrittenLocs) in
    let automaton = get_automaton kf in
    let formals = Kernel_function.get_formals kf in
    let writes =
      WriteFwAnalysis.fixpoint automaton (WrittenLocs.initial formals)
    in
    let e_effects =
      let interproc_args = if options.interproc then Some formals else None in
      get_trans_effects automaton interproc_args writes
    in
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
      | Call (_, exp, _, stmt) when not (is_internal_function exp) ->
        let wl = get_writes_at_v v (Vertex.Hashtbl.find writes v) in
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
