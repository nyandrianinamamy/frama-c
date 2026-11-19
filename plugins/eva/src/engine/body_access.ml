(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Bases = Base.SetLattice
module Zone = Memory_zone

type call_mode = Cache_observation.call_mode

type call_trace = {
  functions : (Cil_types.kernel_function * call_mode) list;
  recursive : bool;
}

module Result = struct
  (* Order used to select one reason for the storage disposition. *)
  type refusal =
    | Indirect_call
    | Reallocation | Allocation | Deallocation | Validity_mutation
    | Recursion | Watchpoint | Dump
    | Builtin | Threaded | Sweep | Widening_hint | Stop_at_alarm
    | Callback | Trace_id | Contract | Annotation | Nested_call
    | Allocated_block | Allocation_metadata | Footprint_top | Side_table

  let refusal_id = function
    | Indirect_call -> "indirect-call"
    | Reallocation -> "reallocation"
    | Allocation -> "allocation"
    | Deallocation -> "deallocation"
    | Validity_mutation -> "validity-mutation"
    | Recursion -> "recursion"
    | Watchpoint -> "watchpoint"
    | Dump -> "dump"
    | Threaded -> "threaded"
    | Widening_hint -> "widening-hint"
    | Stop_at_alarm -> "stop-at-alarm"
    | Callback -> "callback"
    | Trace_id -> "trace-id"
    | Builtin -> "builtin"
    | Sweep -> "sweep"
    | Contract -> "contract"
    | Annotation -> "annotation"
    | Nested_call -> "nested-call"
    | Allocated_block -> "allocated-block"
    | Allocation_metadata -> "allocation-metadata"
    | Footprint_top -> "footprint-top"
    | Side_table -> "side-table"

  type recorded = Cache_observation.recorded =
    | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

  type t = {
    reads : Bases.t;
    dependencies : Bases.t;
    writes : Bases.t;
    exit_writes : Bases.t;
    sure_writes : Base.Hptset.t;
    designated : Bases.t;
    owners : Base.Hptset.t;
    sweeps : Base.Hptset.t;
    used_functions : (Cil_types.kernel_function * call_mode) list;
    hint_generation : Widen_generation.t option;
    recorded : recorded list;
    refusals : refusal list;
    children : Cache_observation.child list;
  }

  module Hooks = Hook.Build (struct type nonrec t = Callstack.t * t end)

  let hint_generation_number = Widen_generation.number

  let on_result f = Hooks.extend (fun (stack, result) -> f stack result)
end

open Result

type writes = { may : Bases.t; sure : Zone.t }

let no_writes = { may = Bases.bottom; sure = Zone.bottom }

type edge = { src : int; dst : int; writes : writes }

module Calls = Set.Make (struct
    type t = Cil_types.kernel_function * call_mode
    let compare (f1, mode1) (f2, mode2) =
      let c = Kernel_function.compare f1 f2 in
      if c <> 0 then c else compare mode1 mode2
  end)

type recording = {
  stack : Callstack.t;
  mutable used_functions : Calls.t;
  entry_generation : Widen_generation.t;
  mutable reads_widening_hints : bool;
  mutable sweeps : Base.Hptset.t;
  mutable reads : Bases.t;
  mutable dependencies : Bases.t;
  call_dependencies : (int, Bases.t) Hashtbl.t;
  mutable transition_src : int option;
  mutable private_blocks : Base.Hptset.t;
  mutable children : Cache_observation.child list;
  enclosing : recording option;
  mutable writes : Bases.t;
  mutable designated : Bases.t;
  mutable owners : Base.Hptset.t;
  mutable recorded : recorded list;
  mutable refusals : refusal list;
  mutable transition : writes option;
  edges : (int, edge) Hashtbl.t;
  mutable paths : (int * int * bool) option;
  mutable unlocated_write : bool;
  mutable exit_possible : Bases.t;
}

let current : recording option ref = ref None

(* The recorder of the body during {!at_call_site}. Footprint operations
   are limited to allocation dependencies there. *)
let call_site : recording option ref = ref None

let[@inline always] is_recording () = Option.is_some !current

let is_observing () = Option.is_some !current || Option.is_some !call_site

let at_site = function
  | Reallocation | Allocation | Deallocation | Validity_mutation
  | Allocated_block | Allocation_metadata | Footprint_top | Watchpoint
  | Stop_at_alarm | Callback | Side_table -> true
  | _ -> false

let add_refusal r reason =
  if not (List.mem reason r.refusals) then r.refusals <- reason :: r.refusals

(* During a requires check, the callee and enclosing body both need
   allocation metadata. *)
let iter_observers f =
  Option.iter f !current;
  Option.iter f !call_site

(* The kernel reports each read of the validity or of the type of an
   allocated block, and each update of a validity record, while a recorder
   is set. *)
let metadata_read base =
  iter_observers (fun r ->
      add_refusal r Allocation_metadata;
      r.owners <- Base.Hptset.add base r.owners)

let validity_update _ ~weak:_ =
  iter_observers (fun r -> add_refusal r Validity_mutation)

(* The observers that the kernel had when the collector installed its own:
   they keep running behind them, and are restored when no recorder is set.
   Another client may install an observer during a recording and forward to
   the one it replaced: an observer of the collector does nothing when it
   is entered again from its own call. *)
let previous_read = ref None
let previous_update = ref None

let forward forwarding f =
  if not !forwarding then begin
    forwarding := true;
    Fun.protect f ~finally:(fun () -> forwarding := false)
  end

let read_observer =
  let forwarding = ref false in
  Some (fun base ->
      forward forwarding (fun () ->
          metadata_read base;
          Option.iter (fun f -> f base) !previous_read))

let update_observer =
  let forwarding = ref false in
  Some (fun validity ~weak ->
      forward forwarding (fun () ->
          validity_update validity ~weak;
          Option.iter (fun f -> f validity ~weak) !previous_update))

(* The observers of the kernel changed by another client while a recorder
   was set: the collector may have missed an event. [displacements] counts
   these changes; a recording that sees the count move is refused. *)
let own_changes = ref 0
let displacements = ref 0

let check_displaced () =
  if (Option.is_some !current || Option.is_some !call_site)
  && Base.observer_changes () <> !own_changes
  then incr displacements

(* Sets the recorders. With a recorder, the observers of the collector are
   the observers of the kernel. Without recorder, the kernel has the
   observers it had before, unless another client installed one during the
   recording: that one is kept, with the collector's behind it. *)
let set_recorders body site =
  check_displaced ();
  current := body;
  call_site := site;
  if Option.is_some body || Option.is_some site then begin
    let top = Base.observe_metadata_reads read_observer in
    if top != read_observer then previous_read := top;
    let top = Base.observe_validity_updates update_observer in
    if top != update_observer then previous_update := top
  end
  else begin
    let top = Base.observe_metadata_reads !previous_read in
    if top == read_observer then previous_read := None
    else ignore (Base.observe_metadata_reads top);
    let top = Base.observe_validity_updates !previous_update in
    if top == update_observer then previous_update := None
    else ignore (Base.observe_validity_updates top)
  end
  ;
  own_changes := Base.observer_changes ()

let with_recorders body site f =
  let previous = !current and previous_site = !call_site in
  set_recorders body site;
  Fun.protect f ~finally:(fun () -> set_recorders previous previous_site)

let without_recording f =
  if Option.is_none !current && Option.is_none !call_site then f ()
  else with_recorders None None f

let at_call_site f =
  match !current with
  | None -> f ()
  | Some r as site -> with_recorders r.enclosing site f

let[@inline always] refuse reason =
  Option.iter (fun r -> add_refusal r reason) !current;
  if at_site reason then
    Option.iter (fun r -> add_refusal r reason) !call_site

let call kf mode =
  Option.iter
    (fun r -> r.used_functions <- Calls.add (kf, mode) r.used_functions)
    !current

let recursion_conflict stack used =
  match Callstack.pop stack with
  | None -> false
  | Some enclosing ->
    let top = Callstack.top_kf stack in
    List.exists
      (fun kf -> Kernel_function.equal kf top ||
                 List.exists (fun (f, _) -> Kernel_function.equal kf f) used)
      (Callstack.to_kf_list enclosing)

let include_trace stack trace =
  Option.iter
    (fun r ->
       let add used call = Calls.add call used in
       r.used_functions <- List.fold_left add r.used_functions trace.functions;
       if trace.recursive || recursion_conflict stack trace.functions
       then add_refusal r Recursion)
    !current

let read_widening_hints () =
  Option.iter (fun r -> r.reads_widening_hints <- true) !current

let record_table r table =
  if not (List.mem table r.recorded) then
    r.recorded <- table :: r.recorded

let[@inline always] record table =
  match !current with
  | None -> ()
  | Some r -> record_table r table

let check_bases r = function
  | Bases.Top -> add_refusal r Footprint_top
  | Bases.Set bases ->
    let allocated = function Base.Allocated _ -> true | _ -> false in
    if Base.Hptset.exists allocated bases then add_refusal r Allocated_block

let add_read r bases =
  check_bases r bases;
  r.reads <- Bases.join r.reads bases;
  let dependencies = Nested_access.remove r.private_blocks bases in
  r.dependencies <- Bases.join r.dependencies dependencies

let[@inline always] read location =
  match !current with
  | None -> ()
  | Some r -> add_read r (Addresses.Bits.get_bases location.Locations.addr)

(* At a requires check, the callee checks blocks without recording the
   accesses as part of its own body. *)
let read_bases bases =
  Option.iter (fun r -> add_read r bases) !current;
  Option.iter (fun r -> check_bases r bases) !call_site

let check_location value =
  if is_observing () then
    let bases = Cvalue.V.get_bases value in
    iter_observers (fun r -> check_bases r bases)

let add_designated r bases =
  let bases =
    match bases with
    | Bases.Top -> Bases.top
    | Bases.Set bases -> Bases.inject (Base.Hptset.remove Base.null bases)
  in
  check_bases r bases;
  r.designated <- Bases.join r.designated bases

let designate_bases bases =
  Option.iter (fun r -> add_designated r bases) !current;
  Option.iter (fun r -> check_bases r bases) !call_site

let[@inline always] designate value =
  if is_observing () then designate_bases (Cvalue.V.get_bases value)

(* A load combines the cells of its range. The combination can drop a
   pointer, for instance beside an uninitialized cell, so the targets of
   every cell that intersects the range are recorded first. *)
let add_cells add_designated state (location : Locations.t) =
  let designate value =
    let value = Cvalue.V_Or_Uninitialized.get_v value in
    add_designated (Cvalue.V.get_bases value)
  in
  let cells base range =
    match Cvalue.Model.find_base_or_default base state, range with
    | `Bottom, _ -> ()
    | `Top, _ -> add_designated Bases.top
    | `Value offsm, None -> Cvalue.V_Offsetmap.iter_on_values designate offsm
    | `Value offsm, Some range ->
      let cell _ (value, _, _) () = designate value in
      Cvalue.V_Offsetmap.fold_between ~entire:true range cell offsm ()
  in
  let range offsets =
    match location.size, Ival.min_and_max offsets with
    | `Value size, (Some min, Some max) -> Some (min, Z.pred (Z.add max size))
    | _ -> None
  in
  match location.addr with
  | Addresses.Bits.Top (Bases.Top, _) -> add_designated Bases.top
  | Addresses.Bits.Top (Bases.Set bases, _) ->
    Base.Hptset.iter (fun base -> cells base None) bases
  | Addresses.Bits.Map map ->
    Addresses.Bits.M.iter (fun base offsets -> cells base (range offsets)) map

let designate_cells state location =
  if is_observing () then add_cells designate_bases state location

let add_exit_write r may sure =
  let may = Nested_access.remove r.private_blocks may in
  r.exit_possible <- Bases.join r.exit_possible may;
  let sure =
    if Base.Hptset.is_empty r.private_blocks then sure
    else Zone.filter_base
        (fun b -> not (Base.Hptset.mem b r.private_blocks)) sure
  in
  match r.transition with
  | None -> r.unlocated_write <- true
  | Some w ->
    let may = Bases.join w.may may in
    let sure = Zone.link w.sure sure in
    r.transition <- Some {may; sure}

let add_write r may sure =
  r.writes <- Bases.join r.writes may;
  add_exit_write r may sure

let add_possible_write r bases =
  check_bases r bases;
  add_write r bases Zone.bottom

let may_write location =
  match !current with
  | None -> ()
  | Some r ->
    add_possible_write r (Addresses.Bits.get_bases location.Locations.addr)

let may_write_base base =
  match !current with
  | None -> ()
  | Some r ->
    add_possible_write r (Bases.inject (Base.Hptset.singleton base))

let unknown_write () =
  Option.iter (fun r -> add_write r Bases.top Zone.bottom) !current

let () = Origin.on_history_access (fun () -> refuse Side_table)

let write location =
  match !current with
  | None -> ()
  | Some r ->
    let may = Addresses.Bits.get_bases location.Locations.addr in
    check_bases r may;
    let sure =
      if Locations.cardinal_zero_or_one location
      then Locations.enumerate_bits_under location
      else Zone.bottom
    in
    add_write r may sure

let unknown_read reason =
  Option.iter
    (fun r ->
       add_refusal r reason;
       r.reads <- Bases.top;
       r.dependencies <- Bases.top)
    !current

let unknown_access reason =
  Option.iter
    (fun r ->
       add_refusal r reason;
       r.reads <- Bases.top;
       r.dependencies <- Bases.top;
       add_write r Bases.top Zone.bottom)
    !current

let sweep ~owner ~inner targets state =
  match !current with
  | None -> false
  | Some r ->
    if Kernel_function.equal owner (Callstack.top_kf r.stack)
    && inner && not (Cvalue.Model.is_top state)
    then begin
      r.sweeps <- Base.Hptset.union targets r.sweeps;
      true
    end
    else begin
      unknown_access Sweep;
      false
    end

let swept_holder base value =
  let bases = Bases.inject (Base.Hptset.singleton base) in
  read_bases bases;
  may_write_base base;
  designate value

let read_message_history () = refuse Side_table

let () = Hook.Opaque.on_call (fun () -> refuse Callback)

let () =
  Log.on_history_access ~audited:true
    (fun ~plugin ~kind ~category ~once_category ->
       let audited =
         plugin = "eva" && not once_category &&
         match kind, category with
         | Log.Feedback, Some ("partition" | "widening") -> true
         | Log.Warning, Some "locals-escaping" -> true
         | _ -> false
       in
       if not audited then read_message_history ())

(* The blocks made weak in the analyses of the current program. A node of
   an offsetmap keeps the tag computed at its first construction, and the
   hash-consing table can return a node built in an earlier analysis: the
   set lasts as long as the bases. *)
module Weakened =
  State_builder.Ref
    (Base.Hptset)
    (struct
      let name = "Eva.Body_access.Weakened"
      let dependencies = [ Ast.self ]
      let default () = Base.Hptset.empty
    end)
let () = Ast.add_monotonic_state Weakened.self

let weakened base = Weakened.set (Base.Hptset.add base (Weakened.get ()))

let read_node_tags () =
  match !current with
  | None -> ()
  | Some r ->
    let bases = Weakened.get () in
    (* The count of the kernel also covers a record made weak by another
       caller than the allocation builtins; its owner is then unknown. *)
    if not (Base.Hptset.is_empty bases) || Base.weakenings () > 0 then begin
      add_refusal r Allocation_metadata;
      r.owners <- Base.Hptset.union bases r.owners
    end

let join_writes left right =
  { may = Bases.join left.may right.may;
    sure = Zone.meet left.sure right.sure }

let map_alternatives ~continues f inputs =
  match !current with
  | Some ({ transition = Some prefix; _ } as r) ->
    let continuing = ref None in
    let run input =
      r.transition <- Some no_writes;
      let output = f input in
      if continues output then begin
        let writes = Option.get r.transition in
        continuing := Some (match !continuing with
            | None -> writes
            | Some previous -> join_writes previous writes)
      end;
      output
    in
    let outputs =
      Fun.protect ~finally:(fun () -> r.transition <- Some prefix)
        (fun () -> List.map run inputs)
    in
    Option.iter (fun writes ->
        r.transition <- Some {
            may = Bases.join prefix.may writes.may;
            sure = Zone.link prefix.sure writes.sure;
          }) !continuing;
    outputs
  | _ -> List.map f inputs

let transfer ~id ~src ~dst f input =
  match !current with
  | None -> f input
  | Some r ->
    let previous = r.transition and previous_src = r.transition_src in
    r.transition <- Some no_writes;
    r.transition_src <- Some src;
    let finish () =
      let writes = Option.get r.transition in
      r.transition <- previous;
      r.transition_src <- previous_src;
      writes
    in
    match f input with
    | exception exn ->
      let bt = Printexc.get_raw_backtrace () in
      ignore (finish ());
      Printexc.raise_with_backtrace exn bt
    | output ->
      let writes = finish () in
      if output <> [] then begin
        let writes =
          match Hashtbl.find_opt r.edges id with
          | None -> writes
          | Some edge -> join_writes edge.writes writes
        in
        Hashtbl.replace r.edges id {src; dst; writes}
      end;
      output

(* The graph contains only transfers that produced a successor. Quotienting
   by the automaton vertices can join paths from different abstract states. *)
let may_reach_exit edges exit =
  let incoming = Hashtbl.create 17 in
  Hashtbl.iter (fun _ e -> Hashtbl.add incoming e.dst e) edges;
  let seen = Hashtbl.create 17 in
  let writes = ref Bases.bottom in
  let rec visit = function
    | [] -> !writes
    | v :: rest when Hashtbl.mem seen v -> visit rest
    | v :: rest ->
      Hashtbl.add seen v ();
      let enqueue rest (e : edge) =
        writes := Bases.join !writes e.writes.may;
        e.src :: rest
      in
      visit (List.fold_left enqueue rest (Hashtbl.find_all incoming v))
  in
  visit [exit]

(* Propagate definitely written bits from the entry. Their intersection at
   a join retains only the bits written on every incoming path. *)
let must_writes edges entry =
  let outgoing = Hashtbl.create 17 in
  Hashtbl.iter (fun _ e -> Hashtbl.add outgoing e.src e) edges;
  let written = Hashtbl.create 17 in
  let work = Queue.create () in
  let enqueue v zone =
    Hashtbl.replace written v zone;
    Queue.push v work
  in
  enqueue entry Zone.bottom;
  while not (Queue.is_empty work) do
    let src = Queue.pop work in
    let before = Hashtbl.find written src in
    let propagate (e : edge) =
      let after = Zone.link before e.writes.sure in
      match Hashtbl.find_opt written e.dst with
      | None -> enqueue e.dst after
      | Some previous ->
        let merged = Zone.meet previous after in
        if not (Zone.equal previous merged) then enqueue e.dst merged
    in
    List.iter propagate (Hashtbl.find_all outgoing src)
  done;
  written

let dependencies r written =
  let at_prefix src reads deps =
    let reads =
      match Hashtbl.find_opt written src with
      | None -> reads
      | Some bits ->
        Nested_access.remove (Nested_access.fully_written bits) reads
    in
    Bases.join reads deps
  in
  Hashtbl.fold at_prefix r.call_dependencies r.dependencies

(* A value that designates an allocated block refuses, with the block as an
   owner; an unknown set of blocks refuses as footprint-top. *)
let check_contents r value =
  match Cvalue.V.get_bases (Cvalue.V_Or_Uninitialized.get_v value) with
  | Bases.Top -> add_refusal r Footprint_top
  | Bases.Set bases ->
    let check = function
      | Base.Allocated _ as base ->
        add_refusal r Allocated_block;
        r.owners <- Base.Hptset.add base r.owners
      | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> ()
    in
    Base.Hptset.iter check bases

let check_state r written state =
  match state with
  | Cvalue.Model.Bottom -> ()
  | Cvalue.Model.Top -> add_refusal r Footprint_top
  | Cvalue.Model.Map _ ->
    let check_block base =
      match Cvalue.Model.find_base base state with
      | exception Not_found -> ()
      | `Bottom -> ()
      | `Top -> add_refusal r Footprint_top
      | `Value offsm ->
        Cvalue.V_Offsetmap.iter_on_values (check_contents r) offsm
    in
    Base.Hptset.iter check_block written

let check_written ~entry ~exits =
  match !current with
  | None -> ()
  | Some r ->
    match r.writes with
    | Bases.Top -> () (* Each unknown write comes with its refusal. *)
    | Bases.Set written ->
      (* The check reads no metadata of the body: its refusals are explicit. *)
      without_recording @@ fun () ->
      if not (Sweep_access.clear_input r.sweeps entry) then add_refusal r Sweep;
      List.iter (check_state r written) (entry :: exits)

let finish_paths ~entry ~exit ~returns =
  Option.iter (fun r -> r.paths <- Some (entry, exit, returns)) !current

let capture stack compute =
  if not (Parameters.CacheCollect.get ()) then compute (), None
  else
    let previous = !current and previous_site = !call_site in
    let r = {
      stack;
      used_functions = Calls.singleton (Callstack.top_kf stack, `Body);
      entry_generation = Widen_generation.current ();
      reads_widening_hints = false;
      sweeps = Base.Hptset.empty;
      reads = Bases.bottom;
      dependencies = Bases.bottom;
      call_dependencies = Hashtbl.create 0;
      transition_src = None;
      private_blocks = Base.Hptset.empty;
      children = [];
      enclosing = previous;
      writes = Bases.bottom;
      designated = Bases.bottom;
      owners = Base.Hptset.empty;
      recorded = [];
      refusals = [];
      transition = None;
      edges = Hashtbl.create 17;
      paths = None;
      unlocated_write = false;
      exit_possible = Bases.bottom;
    } in
    set_recorders (Some r) None;
    let displaced = !displacements in
    let output =
      Fun.protect compute ~finally:(fun () ->
          set_recorders previous previous_site)
    in
    (* Another client changed the observers of the kernel during the
       recording: a read of allocation metadata may be missing. *)
    if !displacements <> displaced then add_refusal r Allocation_metadata;
    (* The size of a written block is read outside the body's analysis. *)
    let exit_writes, sure_writes, dependencies =
      without_recording @@ fun () ->
      let no_sure = Base.Hptset.empty in
      match r.paths with
      | None -> Bases.bottom, no_sure, dependencies r (Hashtbl.create 0)
      | Some (entry, exit, returns) ->
        let written = must_writes r.edges entry in
        let deps = dependencies r written in
        if not returns then Bases.bottom, no_sure, deps
        else if r.unlocated_write then r.exit_possible, no_sure, deps
        else
          let sure =
            match Hashtbl.find_opt written exit with
            | None -> no_sure
            | Some bits -> Nested_access.fully_written bits
          in
          may_reach_exit r.edges exit, sure, deps
    in
    let used_functions = Calls.elements r.used_functions in
    if recursion_conflict stack used_functions then add_refusal r Recursion;
    (* The entry stamp is a valid key only if the hint table remained fixed
       during the body. This also catches a change from nested work. *)
    if r.reads_widening_hints &&
       not (Widen_generation.equal r.entry_generation
              (Widen_generation.current ()))
    then add_refusal r Widening_hint;
    let result = {
      reads = r.reads;
      dependencies;
      writes = r.writes;
      exit_writes;
      sure_writes;
      designated = r.designated;
      owners = r.owners;
      sweeps = r.sweeps;
      used_functions;
      hint_generation =
        (if r.reads_widening_hints then Some r.entry_generation else None);
      recorded = List.sort compare r.recorded;
      refusals = List.sort compare r.refusals;
      children = List.rev r.children;
    } in
    without_recording (fun () -> Hooks.apply (stack, result));
    output, Some result

let verdict (r : Result.t) =
  match r.refusals with
  | [] -> Ok ()
  | reason :: _ -> Error reason

let with_callee kf return f =
  match !current with
  | None -> f ()
  | Some r ->
    let previous = r.private_blocks in
    let blocks = Nested_access.private_blocks kf return in
    r.private_blocks <- Base.Hptset.union previous blocks;
    Fun.protect f ~finally:(fun () -> r.private_blocks <- previous)

let include_call r stack entry ~children ~reads ~deps ~writes ~exit_writes
    ~sure_writes =
  r.reads <- Bases.join r.reads reads;
  r.writes <- Bases.join r.writes writes;
  let deps = Nested_access.remove r.private_blocks deps in
  (match r.transition_src with
   | None -> r.dependencies <- Bases.join r.dependencies deps
   | Some src ->
     let old = Hashtbl.find_opt r.call_dependencies src in
     let old = Option.value ~default:Bases.bottom old in
     Hashtbl.replace r.call_dependencies src (Bases.join old deps));
  let sure =
    (* The bounds here administer the collector, not the analyzed body. *)
    without_recording (fun () -> Nested_access.sure_zone sure_writes)
  in
  add_exit_write r exit_writes sure;
  match Callstack.top_callsite stack with
  | Cil_types.Kglobal -> ()
  | Cil_types.Kstmt stmt ->
    let children =
      match entry with
      | Some entry -> [[stmt], entry]
      | None -> List.map (fun (path, child) -> stmt :: path, child) children
    in
    r.children <- List.rev_append children r.children

let include_effects r ~designated ~recorded =
  r.designated <- Bases.join r.designated designated;
  List.iter (record_table r) recorded

let include_functions r functions =
  r.used_functions <- List.fold_left (fun acc item -> Calls.add item acc)
      r.used_functions functions

let include_fresh stack (body : Result.t) entry =
  Option.iter (fun r ->
      List.iter (add_refusal r) body.refusals;
      if Option.is_some body.hint_generation then
        r.reads_widening_hints <- true;
      if not (Base.Hptset.is_empty body.sweeps) then add_refusal r Sweep;
      r.owners <- Base.Hptset.union r.owners body.owners;
      include_effects r ~designated:body.designated ~recorded:body.recorded;
      include_functions r body.used_functions;
      include_call r stack entry ~children:body.children ~reads:body.reads
        ~deps:body.dependencies ~writes:body.writes
        ~exit_writes:body.exit_writes ~sure_writes:body.sure_writes)
    !current

let include_hit stack entry ~(footprint : Cache_observation.footprint)
    ~key ~returns ~sweeps ~hint_generation ~functions ~observation =
  Option.iter (fun r ->
      let reads = Bases.inject footprint.read
      and writes = Bases.inject footprint.written
      and deps = Bases.inject key
      and exit_writes =
        if not returns then Bases.bottom
        else Bases.inject footprint.written_exit
      in
      List.iter (check_bases r) [reads; writes; deps];
      if Option.is_some hint_generation then r.reads_widening_hints <- true;
      if not (Base.Hptset.is_empty sweeps) then add_refusal r Sweep;
      include_functions r functions;
      (match observation with
       | None -> add_refusal r Nested_call
       | Some Cache_observation.{ designated; recorded } ->
         check_bases r designated;
         include_effects r ~designated ~recorded);
      include_call r stack (Some entry) ~children:[] ~reads ~writes ~deps
        ~exit_writes
        ~sure_writes:(if returns then footprint.written_sure
                      else Base.Hptset.empty))
    !current
