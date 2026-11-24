(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module SaveCounter =
  State_builder.SharedCounter(struct let name = "Mem_exec.save_counter" end)

let new_counter, current_counter =
  let cur = ref (-1) in
  (fun () -> cur := SaveCounter.next (); !cur),
  (fun () -> !cur)

let cleanup_ref = ref (fun () -> ())

(* TODO: it would be great to clear also the tables within the plugins. Export
   self and add dependencies *)
let cleanup_results () = !cleanup_ref ()

exception TooImprecise

type renaming = (Base.t * Base.t) list

(* Extract all the bases from a zone *)
let bases = function
  | Memory_zone.Top (Base.SetLattice.Top, _) -> raise TooImprecise
  | Memory_zone.Top (Base.SetLattice.Set s, _) -> s
  | Memory_zone.Map m -> Base.Hptset.from_map (Memory_zone.shape m)

(* ----- Snapshot of the mentioned blocks ---------------------------------- *)

(* With -eva-hit-log, a call that mentions an allocated block is stored with
   the snapshot of the blocks it mentions, by number, and reused only on
   blocks with the same snapshot. *)

(* The validity record of an allocated block: its bounds, which the analysis
   mutates in place, or a validity that it does not mutate. *)
type record =
  | Variable of { min_alloc: Z.t; max_alloc: Z.t }
  | Fixed of Base.validity

(* What the analysis of a call reads of an allocated block, besides its
   content: its strength, its validity record, its type and its kind. *)
type block = {
  weak: bool;
  record: record;
  typ: Cil_types.typ;
  kind: Base.deallocation;
}

let equal_record r1 r2 =
  match r1, r2 with
  | Variable v1, Variable v2 ->
    Z.equal v1.min_alloc v2.min_alloc && Z.equal v1.max_alloc v2.max_alloc
  | Fixed v1, Fixed v2 -> Base.Validity.equal v1 v2
  | (Variable _ | Fixed _), _ -> false

let equal_block b1 b2 =
  b1.weak = b2.weak && equal_record b1.record b2.record
  && Cil_datatype.Typ.equal b1.typ b2.typ && b1.kind = b2.kind

(* The block of an allocated base as it is now. The record and the type are
   copied: the analysis mutates them in place afterwards. *)
let take_block = function
  | Base.Allocated (vi, kind, validity) ->
    let record =
      match validity with
      | Base.Variable v ->
        Variable { min_alloc = v.min_alloc; max_alloc = v.max_alloc }
      | validity -> Fixed validity
    in
    let weak = Base.is_weak_validity validity in
    Some { weak; record; typ = vi.vtype; kind }
  | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> None

(* The block of an allocated base as it was at the start of a call, which
   has made since then the validity mutations [mutations], see
   [Heap_effects], in the order of emission: each field that a mutation
   changed is taken back to its value before the first mutation that
   changed it. A removal changes no field: the block of a base that the
   call removes is the block it had at the start of the call. The kind of
   a block never changes. *)
let take_block_at_entry ~mutations base =
  let undo block = function
    | Heap_effects.Mutation { block = b; record; weakened; typ }
      when Base.equal b base ->
      let block = if weakened then { block with weak = false } else block in
      let block =
        match record with
        | None -> block
        | Some ({ Heap_effects.min_alloc; max_alloc }, _) ->
          { block with record = Variable { min_alloc; max_alloc } }
      in
      begin match typ with
        | None -> block
        | Some (typ, _) -> { block with typ }
      end
    | Allocation _ | Mutation _ | Removal _ | Sweep _ -> block
  in
  match mutations with
  | [] -> take_block base
  | _ ->
    Option.map
      (fun block -> List.fold_left undo block (List.rev mutations))
      (take_block base)

(* Whether the blocks [b1] and [b2], in the order of their numbers, are
   equal one by one. *)
let equal_blocks b1 b2 = List.equal equal_block b1 b2

(* ----- Heap calls ------------------------------------------------------- *)

(* What memexec stores of a heap call, with -eva-hit-log, see the
   interface. *)
type allocation = {
  block: Base.t;
  suffix: Callstack.call list;
  rank: int;
  size: Cvalue.V.t;
  decision: Heap_effects.decision;
}

type heap = {
  removed: Base.Hptset.t;
  swept: Base.Hptset.t;
  exit: Heap_paths.sweeps;
  mutations: Heap_effects.t list;
  allocations: allocation list;
  candidates: (Callstack.call list * Base.t list) list;
  created: Base.t list;
}

(* The callstack [callstack] extended by the calls [suffix], innermost
   first. *)
let extend (callstack: Callstack.t) suffix =
  { callstack with stack = suffix @ callstack.stack }

(* The calls of [stack] below [callstack], innermost first, if [stack]
   extends [callstack] by at least one call. *)
let suffix_below ~(callstack: Callstack.t) (stack: Callstack.t) =
  let below = List.length stack.stack - List.length callstack.stack in
  if below <= 0
  || stack.thread <> callstack.thread
  || not (Kernel_function.equal stack.entry_point callstack.entry_point)
  then None
  else
    let rec split n acc list =
      if n = 0 then Some (List.rev acc, list)
      else match list with
        | [] -> None
        | call :: rest -> split (n - 1) (call :: acc) rest
    in
    match split below [] stack.stack with
    | Some (suffix, rest)
      when List.equal Callstack.Call.equal rest callstack.stack -> Some suffix
    | Some _ | None -> None

(* The heap calls that memexec stores, per function. *)
let stored_heap_calls =
  Statistics.(register_function_stat "hit-log-stored-heap-calls" Int)

(* Whether the memory state [model] binds [base]. *)
let binds model base =
  match model with
  | Cvalue.Model.Top -> true
  | Bottom -> false
  | Map _ ->
    match Cvalue.Model.find_base base model with
    | _ -> true
    | exception Not_found -> false

(* The pointers to the blocks [every] in [model] become escaping addresses,
   and those to the blocks [some] are joined with escaping addresses, as the
   releases of a call do. Returns the swept model, the cells that the first
   sweep changes, and those that the second one changes, as [free] gives
   them. *)
let sweep_model ~every ~some model =
  let sweep ~exact escaping model =
    if Base.Hptset.is_empty escaping then model, Memory_zone.bottom
    else
      let changed = ref Memory_zone.bottom in
      let on_escaping ~b ~itv ~v:_ =
        let zone = Memory_zone.inject b (Int_Intervals.inject_itv itv) in
        changed := Memory_zone.join !changed zone
      in
      let model =
        Locals_scoping.make_escaping ~exact ~escaping ~on_escaping
          ~within:Base.SetLattice.top model
      in
      model, !changed
  in
  let model, exact = sweep ~exact:true every model in
  let model, joined = sweep ~exact:false some model in
  model, exact, joined


let is_allocated = function
  | Base.Allocated _ -> true
  | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> false

(* Adds to [acc] the allocated bases that [v] may point to. Raises
   [TooImprecise] if [v] may point to an unknown set of bases. *)
let add_targets v acc =
  match Cvalue.V.get_bases v with
  | Base.SetLattice.Top -> raise TooImprecise
  | Base.SetLattice.Set bases ->
    Base.Hptset.union (Base.Hptset.filter is_allocated bases) acc

(* Adds to [acc] the allocated bases that a value of [state] may point to. *)
let add_targets_of_state state acc =
  match state with
  | Cvalue.Model.Bottom -> acc
  | Cvalue.Model.Top -> raise TooImprecise
  | Cvalue.Model.Map map ->
    let add_value v acc =
      add_targets (Cvalue.V_Or_Uninitialized.get_v v) acc
    in
    Cvalue.Model.fold
      (fun _base offsm acc ->
         Cvalue.V_Offsetmap.fold_on_values add_value offsm acc)
      map acc


(* The calls that memexec does not reuse although a stored result has their
   input state in numbered form: the snapshot of a mentioned block
   differs. *)
let snapshot_misses =
  Statistics.(register_function_stat "hit-log-snapshot-misses" Int)

(* The largest number of results that memexec keeps at once for one
   numbered input state of a function, with -eva-hit-log. Outside the
   recursive calls of [store_numbered], their snapshots differ: it is then
   the number of distinct keys of #120, numbered state and snapshot, stored
   for one numbered state. *)
let snapshot_results =
  Statistics.(register_function_stat "hit-log-snapshot-results" Int)

(* The functions called with the entry of each call that memexec stores with
   -eva-hit-log, for the tests. *)
let store_hooks = ref []

let register_store_hook f = store_hooks := !store_hooks @ [ f ]

let counter = ref 0

module Make
    (Value : Engine_abstractions_sig.Value)
    (Domain : Engine_abstractions_sig.Domain)
= struct

  incr counter;

  module CallOutput = Datatype.List (Datatype.Pair (Partition.Key) (Domain))

  module StoredResult =
    Datatype.Triple
      (Base.Hptset)  (* Set of bases possibly read or written by the call. *)
      (CallOutput)   (* The resulting states of the call. *)
      (Datatype.Int) (* Call number, for plugins *)

  (* Map from input states to outputs (summary and state). *)
  module CallEffect = Domain.Hashtbl.Make (StoredResult)

  (* Map from useful input bases to call effects. *)
  module InputBasesToCallEffect = Base.Hptset.Hashtbl.Make (CallEffect)

  (* List of the arguments of a call. *)
  module ActualArgs =
    Datatype.List_with_collections (Datatype.Option (Value)) (* None is bottom *)

  (* Map from the arguments of a call to stored results. *)
  module ArgsToStoredCalls = ActualArgs.Map.Make (InputBasesToCallEffect)

  module PreviousCalls =
    Kernel_function.Make_Table
      (Eva_utils.Do_Not_Marshal (ArgsToStoredCalls))
      (struct
        let size = 17
        let dependencies = [Self.state]
        let name = "Mem_exec.PreviousCalls(" ^ string_of_int !counter ^ ")"
      end)

  (* ----- Calls stored in numbered form ------------------------------------ *)

  (* With [~snapshot:true] (option -eva-hit-log), a call that mentions an
     allocated block is stored in numbered form (#120, section "Lookup"):
     its arguments, its key, its start state on its key and its states at
     the exits, with the placeholder of its number in place of each
     allocated block, see [Numbering]. *)

  (* An allocation of a heap call, numbered: the number of the block it
     creates or reuses, the calls from the call down to the allocation, its
     rank on this stack, the size requested and the decision of the
     policy. *)
  type replayed = {
    number: int;
    suffix: Callstack.call list;
    rank: int;
    size: Cvalue.V.t;
    decision: Heap_effects.decision;
  }

  (* What memexec keeps of a heap call, numbered: the blocks it removes, those
     it sweeps at any point of its body, those it swept on every path from
     its start to its return and on some path only, and its allocations, in
     their order, which a reuse replays. *)
  type numbered_heap = {
    removed_numbers: Base.Hptset.t;
    swept_numbers: Base.Hptset.t;
    every: Base.Hptset.t;
    some: Base.Hptset.t;
    replay: replayed list;
  }

  (* A result stored in numbered form: the output bases and the states at
     the exits, numbered; the call number; the snapshot, the block of each
     number at the start of the call; the blocks of the call that computed
     the result, by number, those that existed at its start and those it
     created, in the order of their creation; and, for a heap call, its
     removals, sweeps and allocations. *)
  type numbered_result = {
    output_bases: Base.Hptset.t;
    outputs: (Partition.key * Domain.t) list;
    call_number: int;
    blocks: block list;
    analysed: Base.t list;
    created: Base.t list;
    heap: numbered_heap option;
  }

  (* A key in numbered form, with the results stored for it by numbered
     start state. [others] are its blocks that are not allocated, and
     [key_numbers] the numbers of its placeholders. [no_root] are the blocks
     that the store numbered as allocated blocks of the key reached from no
     root: a lookup finds them by their identity, as no value leads to them.
     [suffixes] are the calls from the call down to each allocation of a
     heap call, by the order of the first allocation on each, and
     [candidate_numbers] the numbers of the candidates of each: the blocks
     that the policy [by_stack] had made on its stack before the call. *)
  type numbered_key = {
    key: Base.Hptset.t;
    others: Base.Hptset.t;
    key_numbers: Datatype.Int.Set.t;
    no_root: Base.t list;
    suffixes: Callstack.call list list;
    candidate_numbers: int list list;
    results: numbered_result Domain.Hashtbl.t;
  }

  (* The numbered keys stored for numbered arguments, oldest first. *)
  module NumberedKeys =
    Datatype.Make
      (struct
        include Datatype.Undefined
        type t = numbered_key list ref ActualArgs.Map.t
        let name = "Mem_exec.NumberedKeys(" ^ string_of_int !counter ^ ")"
        let reprs = [ ActualArgs.Map.empty ]
        let mem_project = Datatype.never_any_project
      end)

  module NumberedCalls =
    Kernel_function.Make_Table
      (NumberedKeys)
      (struct
        let size = 17
        let dependencies = [Self.state]
        let name = "Mem_exec.NumberedCalls(" ^ string_of_int !counter ^ ")"
      end)

  let cleanup = !cleanup_ref
  let () =
    cleanup_ref :=
      fun () -> cleanup (); PreviousCalls.clear (); NumberedCalls.clear ()

  (* Extends the input [bases] of a function [kf] by adding all bases related to
     these inputs in state [state]. We perform a fixpoint over [Domain.relate]
     to compute the transitive closure of the relations in [state] on [bases].
     Indeed, if a domain D1 relates x and y, and a domain D2 relates y and z,
     then x and z are also related.
     All bases related to the input [bases] should be taken into account when
     applying the memexec cache, as their values may impact the analysis of [kf]
     starting from state [state].
     As a full fixpoint computation could be costly, we stop after [count] calls
     to [Domain.relate] and we disable memexec if a fixpoint is not reached. *)
  let rec expand_inputs_with_relations count kf bases state =
    let related_bases = Domain.relate bases state in
    match related_bases with
    | Base.SetLattice.Top -> related_bases
    | Base.SetLattice.Set new_bases ->
      let expanded_bases = Base.Hptset.union new_bases bases in
      if Base.Hptset.equal expanded_bases bases
      then Base.SetLattice.inject expanded_bases
      else if count <= 0 then Base.SetLattice.top
      else expand_inputs_with_relations (count - 1) kf expanded_bases state

  let get_cvalue =
    match Value.get Main_values.CVal.key with
    | Some get -> get
    | None -> fun _ -> Cvalue.V.top

  (* The allocated bases that a call mentions: the bases of its key [bases],
     and those that a pointer value of its arguments [args] or of [state],
     its start state on its key, may point to. A mentioned base outside the
     key is not entered. Raises [TooImprecise] if one of these values may
     point to an unknown set of bases. *)
  let mentioned_blocks bases args state =
    let add_arg acc = function
      | `Bottom -> acc
      | `Value v -> add_targets (get_cvalue v) acc
    in
    let blocks = Base.Hptset.filter is_allocated bases in
    let blocks = List.fold_left add_arg blocks args in
    add_targets_of_state (Domain.get_cvalue_or_top state) blocks

  let get_cvalue_state = Domain.get Cvalue_domain.State.key

  (* Calls the hooks of the tests with the cvalue part of the entry of a
     call of [kf] just stored, if the domain has the cvalue domain. *)
  let notify_store kf args
      (input_bases, state_input, outputs, created, call_number) =
    match !store_hooks, get_cvalue_state with
    | [], _ | _, None -> ()
    | hooks, Some get ->
      let entry =
        Numbering.{
          args = List.map (Lattice_bounds.Bottom.map get_cvalue) args;
          key = input_bases;
          start = get state_input;
          exits = List.map (fun (_, state) -> get state) outputs;
          created; }
      in
      List.iter (fun hook -> hook kf call_number entry) hooks

  (* ----- Rewriting through a numbering ------------------------------------ *)

  (* The numbered form exists for the cvalue domain only. Option -eva-hit-log,
     the only one that stores calls in numbered form, requires the cvalue
     domain alone: the cvalue component of an argument and of a state is
     then the whole of it. *)

  (* Raised when a call that mentions an allocated block has no numbered
     form: a block of its exits or of its clobbered sets is not numbered, or
     the domain has no cvalue component. *)
  exception No_numbered_form

  let rewrite_argument substitution = function
    | `Bottom -> None
    | `Value v ->
      let cvalue = snd (Cvalue.V.replace_base substitution (get_cvalue v)) in
      Some (Value.set Main_values.CVal.key cvalue v)

  let rewrite_arguments substitution args =
    List.map (rewrite_argument substitution) args

  (* Rewrites the memory state of [state] and its clobbered set. The
     clobbered set is a new record. *)
  let rewrite_state substitution state =
    match get_cvalue_state with
    | None -> raise No_numbered_form
    | Some get ->
      let model, clobbered = get state in
      let model = Numbering.rewrite_model substitution model
      and clobbered = Numbering.rewrite_clobbered substitution clobbered in
      Domain.set Cvalue_domain.State.key (model, clobbered) state

  (* The snapshot of the blocks of [numbering], by number, as they were at
     the start of a call that has made since then the validity mutations
     [mutations]: as they are now, for a call of a lookup. *)
  let snapshot_of ?(mutations = []) numbering =
    List.filter_map (fun (base, _, _) -> take_block_at_entry ~mutations base)
      (Numbering.blocks numbering)

  (* Stores in numbered form the call of [kf] with arguments [args], key
     [input_bases] and start state on its key [state_input], whose exits are
     [outputs], copied on [output_bases] on a reuse. For a heap call, [heap]
     gives its removals, its sweeps and its allocations: the key holds the
     blocks it removes and the candidates of its allocations, and not the
     blocks it creates, which [output_bases] holds. The blocks are numbered
     in the order of #120: from the arguments and the key, then the
     candidates, by stack in the order of the first allocation on each, and
     by rank, then the blocks of the key reached from no root, then the
     blocks the call creates, in the order of their creation, the creation
     symbols. Every block that the call sweeps or allocates must be numbered.
     The snapshot is that of the start of the call, rebuilt from the blocks as
     they are now and from the validity mutations of the call, see
     [take_block_at_entry]; it covers the blocks that exist at the start of
     the call, not the creation symbols. The start state, the arguments and
     the key are numbered with the strength of each block at the start of
     the call, and the exits, the output bases and the blocks of the heap
     effects with its strength now, at the end of the call: the pools of the
     placeholders give each state the strengths that it was built with.
     Returns the numbered blocks, in the order of their numbers. Raises
     [No_numbered_form] and [TooImprecise].
     A result is added only after the lookup of the same call missed. That
     lookup numbers the call as the store does: from its arguments, then
     along the stored key equal to its own, with the same blocks reached
     from no root. So it finds any result stored before it with the same
     numbered start state and a snapshot equal to that of the call. The
     results kept for one numbered start state thus have distinct
     snapshots, except for recursive calls analysed under
     -eva-unroll-recursive-calls: a call with the same numbered start state
     and snapshot, analysed inside this one, is stored after the lookup of
     this one, and both are kept, one per analysed level of the recursion.
     No result is removed, and the lookup tries them one by one. *)
  let store_numbered ?heap kf args ~input_bases ~state_input ~output_bases
      ~outputs call_number =
    let get =
      match get_cvalue_state with
      | None -> raise No_numbered_form
      | Some get -> get
    in
    let cvalue_args = List.map (Lattice_bounds.Bottom.map get_cvalue) args in
    let model, clobbered = get state_input in
    let mutations, candidates, created =
      match heap with
      | None -> [], [], []
      | Some heap -> heap.mutations, heap.candidates, heap.created
    in
    let numbering =
      let weak =
        match mutations with
        | [] -> None
        | _ ->
          Some
            (fun base ->
               match take_block_at_entry ~mutations base with
               | Some block -> block.weak
               | None -> Base.is_weak base)
      in
      try
        Numbering.of_entry ?weak ~candidates:(List.concat_map snd candidates)
          ~args:cvalue_args ~key:input_bases model
      with Numbering.Unknown_targets -> raise TooImprecise
    in
    let blocks = snapshot_of ~mutations numbering in
    let analysed =
      List.map (fun (base, _, _) -> base) (Numbering.blocks numbering)
    in
    let existing = Numbering.length numbering in
    let numbering = Numbering.add Creation created numbering in
    if Numbering.length numbering <> existing + List.length created
    then raise No_numbered_form;
    let to_numbers = Numbering.to_numbers numbering in
    let to_numbers_end =
      match mutations with
      | [] -> to_numbers
      | _ -> Numbering.to_numbers ~weak:Base.is_weak numbering
    in
    let number base =
      match Numbering.number numbering base with
      | Some n -> n
      | None -> raise No_numbered_form
    in
    let heap =
      Option.map
        (fun heap ->
           Base.Hptset.iter (fun base -> ignore (number base)) heap.swept;
           let rewrite = Numbering.rewrite_bases to_numbers_end in
           let replay =
             List.map
               (fun (a: allocation) ->
                  { number = number a.block; suffix = a.suffix; rank = a.rank;
                    size = a.size; decision = a.decision })
               heap.allocations
           in
           { removed_numbers = rewrite heap.removed;
             swept_numbers = rewrite heap.swept;
             every = rewrite heap.exit.Heap_paths.every;
             some = rewrite heap.exit.Heap_paths.some;
             replay; })
        heap
    in
    let rewrite_exit (model, clobbered) =
      Numbering.rewrite_model to_numbers_end model,
      Numbering.rewrite_clobbered to_numbers_end clobbered
    in
    let numbered =
      let start =
        Numbering.rewrite to_numbers
          Numbering.{ args = cvalue_args; key = input_bases;
                      start = model, clobbered; exits = []; created = [] }
      in
      { start with
        exits = List.map (fun (_, state) -> rewrite_exit (get state)) outputs }
    in
    if not (Base.Hptset.is_empty (Numbering.unnumbered numbered))
    then raise No_numbered_form;
    let key = numbered.key in
    let others = Base.Hptset.filter (fun b -> not (is_allocated b)) key in
    let key_numbers =
      Base.Hptset.fold
        (fun base acc ->
           match Numbering.placeholder_number base with
           | Some n -> Datatype.Int.Set.add n acc
           | None -> acc)
        key Datatype.Int.Set.empty
    in
    let no_root =
      List.filter_map
        (fun (base, _, discovery) ->
           match discovery with
           | Numbering.No_root -> Some base
           | Argument _ | Content _ | Candidate | Creation -> None)
        (Numbering.blocks numbering)
    in
    let suffixes = List.map fst candidates in
    let candidate_numbers =
      List.map (fun (_, bases) -> List.map number bases) candidates
    in
    let result = {
      output_bases = Numbering.rewrite_bases to_numbers_end output_bases;
      outputs =
        List.map (fun (k, state) -> k, rewrite_state to_numbers_end state)
          outputs;
      call_number;
      blocks;
      analysed;
      created;
      heap;
    } in
    let args = rewrite_arguments to_numbers args in
    let start = rewrite_state to_numbers state_input in
    let by_args =
      Option.value ~default:ActualArgs.Map.empty (NumberedCalls.find_opt kf)
    in
    let keys =
      match ActualArgs.Map.find_opt args by_args with
      | Some keys -> keys
      | None ->
        let keys = ref [] in
        NumberedCalls.replace kf (ActualArgs.Map.add args keys by_args);
        keys
    in
    let same k =
      Base.Hptset.equal k.key key && List.equal Base.equal k.no_root no_root
      && List.equal (List.equal Callstack.Call.equal) k.suffixes suffixes
      && List.equal (List.equal Int.equal) k.candidate_numbers
        candidate_numbers
    in
    let results =
      match List.find_opt same !keys with
      | Some k -> k.results
      | None ->
        let results = Domain.Hashtbl.create 11 in
        keys :=
          !keys @ [ { key; others; key_numbers; no_root; suffixes;
                      candidate_numbers; results } ];
        results
    in
    Domain.Hashtbl.add results start result;
    Statistics.grow snapshot_results kf
      (List.length (Domain.Hashtbl.find_all results start));
    if Option.is_some heap then Statistics.incr stored_heap_calls kf;
    analysed @ created

  (* With [~snapshot:false], the store of memexec without -eva-hit-log; the
     result is None. With [~snapshot:true], a call that mentions an allocated
     block is stored in numbered form, and any other as without
     -eva-hit-log; the hooks of the tests are called once the call is
     stored, out of the handler of the store. The result is then the blocks
     numbered in the stored call, the empty list if it is not numbered, and
     None if it is not stored. A heap call, with [heap], is stored in
     numbered form only, with the blocks it removes and the candidates of its
     allocations in its key, and the blocks it creates in its output
     bases. *)
  let store_computed_call ~snapshot ?heap kf input_state args
      (call_result: (Partition.key * Domain.t) list) =
    match Transfer_stmt.current_kf_inout () with
    | None -> None
    | Some inout ->
      match
        (* The matching key: the bases read by the call, those read by its
           annotations, and those it writes on any path, whether the path
           returns or not, including the bases it surely overwrites; and,
           for a heap call, the blocks that it removes, which the inout plugin
           does not give, and the candidates of its allocations, without the
           blocks that it creates, which do not exist at its start. *)
        let input_bases =
          let input_bases = bases inout.Inout_type.over_inputs in
          let logic_input_bases = bases inout.Inout_type.over_logic_inputs in
          let output_bases = bases inout.Inout_type.over_outputs in
          Base.Hptset.(union input_bases (union logic_input_bases output_bases))
        in
        let input_bases =
          match heap with
          | None -> input_bases
          | Some heap ->
            let add_candidates acc (_, candidates) =
              List.fold_left (fun acc b -> Base.Hptset.add b acc) acc
                candidates
            in
            let input_bases = Base.Hptset.union input_bases heap.removed in
            let input_bases =
              List.fold_left add_candidates input_bases heap.candidates
            in
            List.fold_left (fun acc b -> Base.Hptset.remove b acc) input_bases
              heap.created
        in
        let input_bases =
          expand_inputs_with_relations 2 kf input_bases input_state
        in
        let input_bases = match input_bases with
          | Base.SetLattice.Top -> raise TooImprecise
          | Base.SetLattice.Set bases -> bases
        in
        let state_input = Domain.filter input_bases input_state in
        let numbered =
          snapshot
          && (Option.is_some heap
              || not (Base.Hptset.is_empty
                        (mentioned_blocks input_bases args state_input)))
        in
        (* Output bases, that is bases that are copy-pasted on a reuse: the
           key, which includes the written bases and the input bases, as the
           latter may get reduced during the call, and the blocks that a
           heap call creates. *)
        let all_output_bases =
          match heap with
          | None -> input_bases
          | Some heap ->
            List.fold_left (fun acc b -> Base.Hptset.add b acc) input_bases
              heap.created
        in
        (* Adds the fake varinfo used for the result of [kf] to the
           output_bases. *)
        let return_varinfo = Library_functions.get_retres_vi kf in
        let return_base = Option.map Base.of_varinfo return_varinfo in
        let add b = Base.Hptset.add b all_output_bases in
        let all_output_bases =
          Option.fold ~some:add ~none:all_output_bases return_base
        in
        let clear (key,state) =
          key, Domain.filter all_output_bases state
        in
        let outputs = List.map clear call_result in
        let call_number = current_counter () in
        let mentioned =
          if numbered
          then
            store_numbered ?heap kf args ~input_bases ~state_input
              ~output_bases:all_output_bases ~outputs call_number
          else begin
            let map_a =
              try PreviousCalls.find kf
              with Not_found -> ActualArgs.Map.empty
            in
            let hkf =
              let args =
                List.map (function `Bottom -> None | `Value v -> Some v) args in
              try ActualArgs.Map.find args map_a
              with Not_found ->
                let h = Base.Hptset.Hashtbl.create 11 in
                let map_a = ActualArgs.Map.add args h map_a in
                PreviousCalls.replace kf map_a;
                h
            in
            let hkb =
              try Base.Hptset.Hashtbl.find hkf input_bases
              with Not_found ->
                let h = Domain.Hashtbl.create 11 in
                Base.Hptset.Hashtbl.add hkf input_bases h;
                h
            in
            Domain.Hashtbl.add hkb state_input
              (all_output_bases, outputs, call_number);
            []
          end
        in
        (* Nothing is built for the hooks without -eva-hit-log. *)
        if snapshot
        then
          let created = match heap with None -> [] | Some h -> h.created in
          Some
            (mentioned,
             (input_bases, state_input, outputs, created, call_number))
        else None
      with
      | exception
          (TooImprecise
          | No_numbered_form
          | Kernel_function.No_Statement
          | Not_found) -> None
      | None -> None
      | Some (mentioned, stored) ->
        notify_store kf args stored;
        Some mentioned


  exception Result_found of CallOutput.t * int

  (* A call stored in numbered form reused through a renaming that is not the
     identity. Without -eva-hit-log, the lookup raises [Result_found] only,
     whose value has the size it had before the renaming. *)
  exception Renamed_result_found of CallOutput.t * int * renaming

  (* A heap call stored in numbered form: the reuse, which replays its
     allocations and sweeps the state, is deferred, see [Replayed_hit]. *)
  exception Replayed_result_found of
      (unit -> CallOutput.t * renaming * Cvalue_callbacks.swept) * int

  type hit =
    | Hit of CallOutput.t * int
    | Renamed_hit of CallOutput.t * int * renaming
    | Replayed_hit of
        (unit -> CallOutput.t * renaming * Cvalue_callbacks.swept) * int

  (** Find a previous execution in [map_inputs] that matches [st].
      raise [Result_found] when this execution exists, or do nothing. This is
      the lookup of the calls stored as without -eva-hit-log. *)
  let find_match_in_previous (map_inputs: InputBasesToCallEffect.t) state =
    let aux_previous_call binputs hstates =
      let brelated = Domain.relate binputs state in
      if not Base.SetLattice.(is_included brelated (inject binputs))
      then ()
      else
        (* restrict [state] to the inputs of this call *)
        let st_filtered = Domain.filter binputs state in
        try
          let bases, outputs, i = Domain.Hashtbl.find hstates st_filtered in
          (* We have found a previous execution, in which the outputs are
             [outputs]. Copy them in [state] and return this result. *)
          let process (key,output) =
            key,
            Domain.reuse bases ~current_input:state ~previous_output:output
          in
          let outputs = List.map process outputs in
          raise (Result_found (outputs, i))
        with Not_found -> ()
    in
    Base.Hptset.Hashtbl.iter aux_previous_call map_inputs

  (* The states at the exits [outputs] of a stored heap call, with its
     removals and sweeps [heap], numbered, reused in the state [state] of a
     call through [of_numbers], and copied on [bases]. For a call that
     allocates, the allocations have been replayed before, and [of_numbers]
     maps its creation symbols to the blocks of the replay. For each exit,
     the pointers of [state] to the blocks that the stored call swept are
     swept: the frame, which the exit does not hold, has in [state] the
     values it had at the start of the call. The exit is then copied on
     [bases], and the blocks that the stored call removed and that the exit
     does not bind are removed: the removal mask. A block swept on some path
     only that the exit does not bind is swept on every path for this exit.
     If the start of the call binds the block, a release that removes it,
     and sweeps the pointers to it in the same step, ran on every path that
     leads to the exit: no state of the exit binds it, and an allocation
     only binds a block, so each of these paths removed the block after the
     start. If the start of the call does not bind the block, the block was
     created or reused by the call, and [state] holds no pointer to it: a
     release sweeps every pointer to the block it removes, and a block
     created by the call does not exist in [state]; the sweep of the block
     on every path or on some path then gives the same state. The state is
     swept once for the exits that sweep the same blocks.
     Also returns the cells outside [bases] that the sweeps change, which
     the exits do not replace, see [Cvalue_callbacks.swept]: those changed
     for some exit or that point to a block that the stored call swept at
     any point, and those changed for every exit by a sweep on every path.
     The cells of [bases] are those of the exit. Before the sweep of a block
     on a path, the call writes no cell outside [bases]: these cells point
     to the block there as at the start of the call, and a call analysed by
     its body reports them as written by the sweep. *)
  let reuse_heap of_numbers heap bases state outputs =
    let get =
      match get_cvalue_state with
      | None -> raise No_numbered_form
      | Some get -> get
    in
    let set model clobbered state =
      Domain.set Cvalue_domain.State.key (model, clobbered) state
    in
    let rewrite = Numbering.rewrite_bases of_numbers in
    let removed = rewrite heap.removed_numbers in
    let every = rewrite heap.every and some = rewrite heap.some in
    let outside =
      Memory_zone.filter_base (fun b -> not (Base.Hptset.mem b bases))
    in
    let swept = ref [] in
    let sweep_state every some =
      let same (e, s, _) =
        Base.Hptset.equal e every && Base.Hptset.equal s some
      in
      match List.find_opt same !swept with
      | Some (_, _, result) -> result
      | None ->
        let model, clobbered = get state in
        let model, exact, joined = sweep_model ~every ~some model in
        let result =
          set model clobbered state, outside exact, outside joined
        in
        swept := (every, some, result) :: !swept;
        result
    in
    let process (key, output) =
      let output = rewrite_state of_numbers output in
      let unbound b = not (binds (fst (get output)) b) in
      let gone = Base.Hptset.filter unbound removed in
      let promoted = Base.Hptset.inter some gone in
      let input, exact, joined =
        sweep_state (Base.Hptset.union every promoted)
          (Base.Hptset.diff some promoted)
      in
      let result =
        Domain.reuse bases ~current_input:input ~previous_output:output
      in
      let model, clobbered = get result in
      (key, set (Base.Hptset.fold Cvalue.Model.remove_base gone model)
         clobbered result),
      (exact, joined)
    in
    let results = List.map process outputs in
    let written, sure =
      match List.map snd results with
      | [] -> Memory_zone.bottom, Memory_zone.bottom
      | (exact, joined) :: rest ->
        List.fold_left
          (fun (written, sure) (exact, joined) ->
             Memory_zone.(join written (join exact joined)),
             Memory_zone.narrow sure exact)
          (Memory_zone.join exact joined, exact) rest
    in
    (* The blocks swept on a path that does not return. *)
    let beyond =
      Base.Hptset.diff (rewrite heap.swept_numbers)
        (Base.Hptset.union every some)
    in
    let written =
      if Base.Hptset.is_empty beyond then written
      else
        let _, _, changed =
          sweep_model ~every:Base.Hptset.empty ~some:beyond (fst (get state))
        in
        Memory_zone.join written (outside changed)
    in
    List.map fst results, { Cvalue_callbacks.written; sure }

  (* Replays the allocation [a] of a stored heap call in a call on
     [callstack] that reuses it, [numbering] being the numbering of the
     lookup, extended by the blocks that the replay has created so far: the
     block that the stored call created is created on the stack of the
     allocation in this call, as the next creation symbol, and the block that
     it reused is reused there, resized through the builtin. The candidate
     condition and the replay of the allocations before [a] make the block of
     rank [a.rank] on this stack the image of the block of [a] by the
     renaming: a block reused at another number fails. *)
  let replay_allocation callstack numbering (a: replayed) =
    let stack = extend callstack a.suffix in
    match a.decision with
    | Heap_effects.Created ->
      if a.number <> Numbering.length numbering then
        Self.fatal "replay of an allocation: creation symbol %d, expected %d"
          a.number (Numbering.length numbering);
      let base = Builtins_malloc.replay_creation ~stack ~rank:a.rank a.size in
      Numbering.add Creation [ base ] numbering
    | Reused { weakened } ->
      let base =
        Builtins_malloc.replay_reuse ~stack ~rank:a.rank ~weakened a.size
      in
      if Numbering.number numbering base <> Some a.number then
        Self.fatal "replay of an allocation: block %a reused for number %d"
          Base.pretty base a.number;
      numbering

  (* The lookup of a call on [callstack] in the keys [keys] stored in
     numbered form for its numbered arguments, [numbering] being the
     numbering of its arguments. For each key, the numbering continues on
     [state], guided by the key: a block whose number is that of a
     placeholder of the key is entered, the candidates of the allocations of
     the key are numbered, from the lists of the blocks that the policy
     [by_stack] made on the stack of each allocation in this call, and the
     blocks of the key reached from no root are taken by their identity. The
     candidate condition: for each allocation stack, the candidates of the
     call have the numbers that the stored key recorded, in the same order;
     the key is skipped otherwise. The key of the call is the image of the
     stored key; the state projected on it, rewritten with numbers, is looked
     up. A stored result matches if its snapshot holds for the blocks of the
     numbering: the most recent one if several do. Its exits, their
     clobbered sets and its output bases are rewritten back through the
     numbering. Raises [Renamed_result_found] with the renaming from the
     blocks of the call that computed the result to those of this call, by
     number, or [Result_found] if it is the identity. For a result of a
     heap call, raises [Replayed_result_found] with the reuse instead, which
     nothing has run: it replays the allocations in their order, if any,
     then rewrites the exits through the numbering extended by the blocks of
     the replay, with the strength of each block after the replay, sweeps
     the state and copies the exits, see [reuse_heap], and gives the
     renaming, which also maps the blocks that the stored call created to
     those of the replay, the empty list if it is the identity, and the
     cells that the sweeps change outside the exits. Returns whether a
     result has the numbered input state of the call but no snapshot that
     holds.
     A result whose snapshot fails is kept: it is no longer tied to one
     block, and can hold at a later lookup on other blocks. *)
  let find_numbered ~callstack keys numbering state =
    let model =
      match get_cvalue_state with
      | None -> raise No_numbered_form
      | Some get -> fst (get state)
    in
    let same_input = ref false in
    let lookup k =
      let is_key n _ = Datatype.Int.Set.mem n k.key_numbers in
      let candidates =
        List.map
          (fun suffix -> Builtins_malloc.malloced_on (extend callstack suffix))
          k.suffixes
      in
      match
        Numbering.of_key ~is_key ~others:k.others
          ~candidates:(List.concat candidates) ~no_root:k.no_root model
          numbering
      with
      | exception Numbering.Unknown_targets -> ()
      | numbering ->
        let candidate_numbers =
          List.map (List.map (Numbering.number numbering)) candidates
        in
        let stored =
          List.map (List.map Option.some) k.candidate_numbers
        in
        if List.equal (List.equal (Option.equal Int.equal)) stored
            candidate_numbers
        then
          let add n acc =
            match Numbering.block numbering n with
            | Some base -> Base.Hptset.add base acc
            | None -> raise Not_found
          in
          match Datatype.Int.Set.fold add k.key_numbers k.others with
          | exception Not_found -> ()
          | key ->
            let to_numbers = Numbering.to_numbers numbering in
            let related = Domain.relate key state in
            if Base.Hptset.equal (Numbering.rewrite_bases to_numbers key) k.key
            && Base.SetLattice.(is_included related (inject key))
            then
              let start = rewrite_state to_numbers (Domain.filter key state) in
              match Domain.Hashtbl.find_all k.results start with
              | [] -> ()
              | results ->
                let now = snapshot_of numbering in
                match
                  List.find_opt (fun r -> equal_blocks r.blocks now) results
                with
                | None -> same_input := true
                | Some r ->
                  let blocks =
                    List.map (fun (base, _, _) -> base)
                      (Numbering.blocks numbering)
                  in
                  match r.heap with
                  | Some heap ->
                    let replay () =
                      let numbering, of_numbers =
                        match heap.replay with
                        | [] -> numbering, Numbering.of_numbers numbering
                        | replay ->
                          let numbering =
                            List.fold_left (replay_allocation callstack)
                              numbering replay
                          in
                          numbering,
                          Numbering.of_numbers ~weak:Base.is_weak numbering
                      in
                      let bases =
                        Numbering.rewrite_bases of_numbers r.output_bases
                      in
                      let outputs, swept =
                        reuse_heap of_numbers heap bases state r.outputs
                      in
                      let replayed =
                        List.filter_map
                          (fun (base, _, discovery) ->
                             match discovery with
                             | Numbering.Creation -> Some base
                             | Argument _ | Content _ | Candidate | No_root ->
                               None)
                          (Numbering.blocks numbering)
                      in
                      let renaming =
                        List.combine r.analysed blocks
                        @ List.combine r.created replayed
                      in
                      let identity (b, image) = Base.equal b image in
                      outputs,
                      (if List.for_all identity renaming then [] else renaming),
                      swept
                    in
                    raise (Replayed_result_found (replay, r.call_number))
                  | None ->
                    let of_numbers = Numbering.of_numbers numbering in
                    let bases =
                      Numbering.rewrite_bases of_numbers r.output_bases
                    in
                    let outputs =
                      let process (key, output) =
                        key,
                        Domain.reuse bases ~current_input:state
                          ~previous_output:(rewrite_state of_numbers output)
                      in
                      List.map process r.outputs
                    in
                    if List.equal Base.equal r.analysed blocks
                    then raise (Result_found (outputs, r.call_number))
                    else
                      let renaming = List.combine r.analysed blocks in
                      raise
                        (Renamed_result_found
                           (outputs, r.call_number, renaming))
    in
    List.iter lookup keys;
    !same_input

  (* The lookup of a call on [callstack] with -eva-hit-log in the calls
     stored in numbered form. Returns whether the snapshot of a block made it
     miss. *)
  let find_match_numbered ~callstack kf state args =
    match NumberedCalls.find_opt kf with
    | None -> false
    | Some by_args ->
      let cvalue_args = List.map (Lattice_bounds.Bottom.map get_cvalue) args in
      match Numbering.arguments cvalue_args Numbering.empty with
      | exception Numbering.Unknown_targets -> false
      | numbering ->
        let to_numbers = Numbering.to_numbers numbering in
        match
          ActualArgs.Map.find_opt (rewrite_arguments to_numbers args) by_args
        with
        | None -> false
        | Some keys -> find_numbered ~callstack !keys numbering state

  (* The lookup of a call in the calls stored as without -eva-hit-log.
     Raises [Not_found] if none has its arguments. *)
  let find_previous kf state args =
    let previous_kf = PreviousCalls.find kf in
    let args = List.map (function `Bottom -> None | `Value v -> Some v) args in
    let previous = ActualArgs.Map.find args previous_kf in
    find_match_in_previous previous state

  (* With [~snapshot:false], the lookup of memexec without -eva-hit-log. With
     [~snapshot:true], the calls stored as without -eva-hit-log are looked
     up first, then those stored in numbered form. *)
  let reuse_previous_call ~snapshot ~callstack kf state args =
    try
      if not snapshot then find_previous kf state args
      else begin
        (try find_previous kf state args with Not_found -> ());
        if find_match_numbered ~callstack kf state args
        then Statistics.incr snapshot_misses kf
      end;
      Statistics.(incr memexec_misses kf);
      None
    with
    | Not_found | No_numbered_form ->
      Statistics.(incr memexec_misses) kf;
      None
    | Result_found (outputs, i) ->
      Statistics.(incr memexec_hits) kf;
      let call_result = outputs in
      Some (Hit (call_result, i))
    | Renamed_result_found (outputs, i, renaming) ->
      Statistics.(incr memexec_hits) kf;
      Some (Renamed_hit (outputs, i, renaming))
    | Replayed_result_found (replay, i) ->
      Statistics.(incr memexec_hits) kf;
      Some (Replayed_hit (replay, i))

  let has_previous_call kf state args =
    try
      let previous_kf = PreviousCalls.find kf in
      let args =
        List.map (function `Bottom -> None | `Value v -> Some v) args
      in
      let previous = ActualArgs.Map.find args previous_kf in
      find_match_in_previous previous state;
      false
    with
    | Not_found -> false
    | Result_found _ -> true

end
