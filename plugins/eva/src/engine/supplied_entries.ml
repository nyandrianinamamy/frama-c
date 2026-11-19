(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Entry = Cache_entry.Cvalue

type entry = Entry.t

type footprint = Cache_entry.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

module Entries =
  Datatype.Make
    (struct
      include Datatype.Undefined
      type t = Entry.t list
      let name = "Eva.Supplied_entries.Entries"
      let reprs = [ [] ]
      let mem_project = Datatype.never_any_project
    end)

(* Entries supplied for each function, oldest first. *)
module Table =
  Kernel_function.Make_Table
    (Eva_utils.Do_Not_Marshal (Entries))
    (struct
      let size = 7
      let dependencies = [ Ast.self ]
      let name = "Eva.Supplied_entries.Table"
    end)

module Counter =
  State_builder.Counter (struct let name = "Eva.Supplied_entries.Counter" end)

let entries kf = Option.value ~default:[] (Table.find_opt kf)

(* The clobbered set of a state: the blocks bound in [model] that may hold
   the address of a local or formal variable. *)
let holders model =
  match model with
  | Cvalue.Model.Top -> Locals_scoping.top ()
  | Bottom -> Locals_scoping.bottom ()
  | Map m ->
    let add b offsetmap acc =
      if Locals_scoping.offsetmap_contains_local offsetmap
      then Base.Hptset.add b acc
      else acc
    in
    let clob = Locals_scoping.bottom () in
    let bases = Cvalue.Model.fold add m Base.Hptset.empty in
    Locals_scoping.remember_bases_with_locals clob
      (Base.SetLattice.inject bases);
    clob

(* Whether block [b] exists at the exit of the body of [kf]: all blocks do
   but the locals of its inner blocks, which leave their scope before. *)
let exists_at_exit kf b =
  match b with
  | Base.Var (vi, _) when Kernel_function.is_local vi kf ->
    let fundec = Kernel_function.get_definition kf in
    List.exists (Cil_datatype.Varinfo.equal vi) fundec.sbody.blocals
  | _ -> true

(* [model] is a map: [supply] refuses Top and Bottom exit states. *)
let binds model b =
  match Cvalue.Model.find_base b model with
  | _ -> true
  | exception Not_found -> false

(* [reuse] on cvalue keeps the value of the input for a block of W_exit that
   the exit state does not bind: each exit state must bind every block of
   W_exit that exists at the exit. *)
let check_exit kf entry =
  let check (_, (model, _)) b =
    if exists_at_exit kf b && not (binds model b) then
      Format.kasprintf invalid_arg
        "Supplied_entries.supply: an exit state does not bind the block %a, \
         written on a path to an exit" Base.pretty b
  in
  let written = (Entry.footprint entry).written_exit in
  List.iter (fun s -> Base.Hptset.iter (check s) written) (Entry.exit entry)

let check_exit_state (_, model) =
  if Cvalue.Model.is_top model then
    invalid_arg "Supplied_entries.supply: an exit state is Top";
  if not (Cvalue.Model.is_reachable model) then
    invalid_arg
      "Supplied_entries.supply: an exit state is Bottom; a body that never \
       returns has no exit state"

(* Whether the body of [kf] may call a function that has a body: a call to a
   function with a definition, or through a pointer. A hit skips the analysis
   of the called functions as well as that of [kf], and only [kf] is recorded
   among the functions with skipped visits (see {!Safety_delivery}). [supply]
   refuses such a body before any lookup; the lookup rejects the entries of
   the bodies with another call ({!has_nested_call}), produced entries
   included. *)
let calls_a_body kf =
  let is_body f = Kernel_function.is_definition (Globals.Functions.get f) in
  let calls stmt =
    match stmt.Cil_types.skind with
    | Instr (Call (_, f, _, _)) ->
      begin match Kernel_function.get_called f with
        | None -> true
        | Some callee -> Kernel_function.is_definition callee
      end
    | Instr (Local_init (_, ConsInit (f, _, _), _)) -> is_body f
    | _ -> false
  in
  List.exists calls (Kernel_function.get_definition kf).sallstmts

let check_no_call kf =
  if calls_a_body kf then
    Format.kasprintf invalid_arg
      "Supplied_entries.supply: the body of %a may call a function that has \
       a body" Kernel_function.pretty kf
(* A function of another project, for instance the project from which the
   current one was copied, is a distinct value with the same identifier:
   comparing it with the functions of the current project is an internal
   error. *)
let check_project kf =
  match Globals.Functions.get (Kernel_function.get_vi kf) with
  | current when current == kf -> ()
  | _ | exception Not_found ->
    Format.kasprintf invalid_arg
      "Supplied_entries: the function %s of the entry is not a function of \
       the current project; entries are supplied to the project whose AST \
       they were made on"
      (Kernel_function.get_name kf)

let add kf entry =
  check_project kf;
  ignore (Counter.next ());
  Table.replace kf (entries kf @ [ entry ]);
  entry

let supply ?safety ?reach kf ~key ~input ~footprint ~exit =
  check_no_call kf;
  (* A call whose input is [Top] would match an entry whose input is [Top],
     and [reuse] would then return the exit state alone, without the blocks
     of the caller. No call is analysed from [Bottom]. *)
  if not (Cvalue.Model.is_reachable input) || Cvalue.Model.is_top input then
    invalid_arg "Supplied_entries.supply: the input is Top or Bottom";
  (* [reuse] of a Top exit state is Top, which loses the blocks of the
     caller. An exit state that is Bottom describes no execution. *)
  List.iter check_exit_state exit;
  let exit = List.map (fun (k, s) -> k, (s, holders s)) exit in
  let input = input, Locals_scoping.bottom () in
  let id = Counter.get () + 1 in
  let entry =
    Entry.make ~id ?safety ?reach (Body kf) ~key ~input ~footprint ~exit
  in
  check_exit kf entry;
  add kf entry

let supply_produced produced =
  let entry = Cache_producer.cache_entry produced in
  let Cache_entry.Body kf = Entry.statement entry in
  add kf (Entry.with_id (Counter.get () + 1) entry)

let empty_key = Partition.Key.empty

let case_key kf rank =
  let stmt = Kernel_function.find_return kf in
  Partition.(Key.add_branch (Disjunction_case { stmt; rank }) Key.empty)

let return_variable = Library_functions.get_retres_vi

let clear () = Table.clear ()

(* Whether the current analysis uses the supplied entries. It is decided when
   the analysis starts, so that no analysis has both caches. *)
module Active =
  State_builder.Ref (Datatype.Bool)
    (struct
      let name = "Eva.Supplied_entries.Active"
      let dependencies = [ Ast.self ]
      let default () = false
    end)

let () =
  Cvalue_callbacks.register_at_start_hook
    (fun () -> Active.set (Table.length () > 0))

let active = Active.get

let id = Entry.id
let statement = Entry.statement
let key = Entry.key
let input e = fst (Entry.input e)
let footprint = Entry.footprint
let exit e = List.map (fun (k, (s, _)) -> k, s) (Entry.exit e)
let safety = Entry.safety
let reach = Entry.reach
let parts = Entry.parts
let pretty = Entry.pretty

type rejection =
  [ Cache_entry.rejection | `Product | `Consumer | `Stop_at_nth_alarm
  | `Callback | `Analysis_reset ]

let rejections : rejection list =
  [ `Key_differs; `Key_unclosed; `Missing_part; `Sweep; `Recursion;
    `Hint_generation; `Watchpoint; `Automatic_cleanup; `Nested_delivery;
    `Warn_categories; `Missing_points; `Preconditions; `Product; `Consumer;
    `Stop_at_nth_alarm; `Callback; `Analysis_reset ]

let rejection_id : rejection -> string = function
  | #Cache_entry.rejection as r -> Cache_entry.rejection_id r
  | `Product -> "product"
  | `Consumer -> "consumer"
  | `Stop_at_nth_alarm -> "stop-at-nth-alarm"
  | `Callback -> "callback"
  | `Analysis_reset -> "analysis-reset"

type 'state lookup = {
  rejected : (int * rejection) list;
  hit : (entry * (Partition.key * 'state) list) option;
  restoration : Cache_part.restoration;
}

(* The analysis of threads resolves the identifier given with [`Reuse] to the
   callbacks in its tables of memexec results, and owns no part. The callwise
   results of Inout and From are parts of the entries (see {!Cache_part});
   their analyses by function read the states saved at statements. The other
   plug-ins below read the states saved at the statements of a function,
   and a hit saves none for its own visits: Nonterm reports the statements
   without a state as unreachable or non-terminating, Metrics and the
   Markdown report count them as unreached, WP takes the states as
   hypotheses of its memory model based on Eva, and the constant propagation
   replaces an expression by its value in these states. *)
let state_readers = [ "nonterm"; "metrics"; "mdr"; "wp"; "scf" ]

let consumer_enabled parts =
  List.exists Plugin.is_present state_readers
  || Mt_options.Enabled.get () || Cache_part.reads_statement_states parts

(* A fresh evaluation emits all the alarms of an evaluation before it tests
   the threshold of [-eva-stop-at-nth-alarm]; a hit delivers the alarms one
   by one, and does not know the evaluations they came from. *)
let stop_at_nth_alarm () = Parameters.StopAtNthAlarm.get () < max_int

(* The states of the tree that depend on the statuses of the properties,
   by their unique names. The emission of a status ([Property_status.emit])
   clears them in the current project, by their own functions, and applies
   their hooks on an update. The states of the kernel hold the consolidated
   statuses, which are computed again from the emitted ones at the next
   request; those of Report hold a flag that makes it print its report
   again, and count when Report is loaded. Metrics has another one, and
   its presence rejects every entry ({!state_readers}). *)
let kernel_status_dependents =
  [ "Consolidation graph";
    "Property_status.Consolidated_status";
    "Property_status.Hypotheses";
    "Property_status.Valid_cycles" ]

let report_status_dependents =
  [ "Report.classify_once"; "Report.print_csv_once"; "Report.print_once" ]

(* Whether the emission of a status runs client code through a state that
   depends on the statuses: the clearing function of a state that is not
   one of those above, or a hook on the update of any of them. *)
let unaudited_status_dependents () =
  let known =
    if Plugin.is_present "report"
    then kernel_status_dependents @ report_status_dependents
    else kernel_status_dependents
  in
  let unaudited state =
    not (List.mem (State.get_unique_name state) known)
    || State.has_hooks_on_update state
  in
  let selection = State_selection.only_dependencies Property_status.self in
  State_selection.fold (fun state found -> found || unaudited state)
    selection false

(* Whether a client that is not audited is registered on a hook that a hit
   runs between its lookup and the end of its delivery, or that an analysis
   of the body runs and a hit does not. Such a client can tell a hit from an
   analysis of the body, and change what follows. The hooks are:
   - the call, call results and statement hooks of Eva, apart from those
     registered with [cache_protocol] or [classified];
   - the hooks of red statuses, which have no audited client;
   - the hooks of the kernel on a new property and on a new status, which
     the delivery of alarms and statuses runs, and on a change of the
     annotations, which the registration of an alarm runs, apart from the
     hook of the server, which emits a signal to its client;
   - the actions registered before and after the clearing of a project,
     apart from the one of the server, which drops the content that it
     keeps for its arrays: the emission of a status clears the states that
     depend on the statuses, and so runs them;
   - the states that depend on the statuses, apart from those of the kernel
     and of Report, and the hooks on the update of any of them
     ({!unaudited_status_dependents}): the emission of a status runs their
     clearing functions and these hooks;
   - the function of [Cil.typeForInsertedCast], other than the default one,
     and the hooks on the table of logic functions: an analysis of the body
     builds the predicate of an alarm, with casts and, for some alarms, a
     built-in predicate added to the table at its first use; a hit registers
     the predicate that its entry holds, and builds none;
   - the listeners and the observers of the history of the logger, apart
     from the message collector of the kernel and the observer of the
     collector of block accesses, and the hooks of the message collector:
     the line of the call, the messages of the statuses and the reports of
     the alarms reach them;
   - the restoration of the parts whose consumer is enabled, and the clients
     that it runs, apart from those registered as audited (see
     {!Cache_part.register}), by the decisions [parts] that the lookup took
     before this test;
   - the subscribers of the statistics by function of the summary, which the
     end of a delivery updates, apart from those registered as audited;
   - the observers of the calls of the clients of the kernel hooks wrapped
     by [Hook.Opaque], which the hook of the server on the annotations and
     the hooks of the properties and messages run, apart from the observer
     of the collector of block accesses;
   - the observers of the reads of the metadata of the allocated bases and
     of the updates of their validity, which the evaluation of the alarms
     runs, and the observers of the accesses to the history of the origins,
     apart from those of the collector;
   - the daemons of [Async], which the analysis of a body runs at its
     statements, and a hit does not: the server registers one while it
     runs;
   - the hooks on a change of the current location of the kernel, which the
     analysis of a body changes at each statement, and of the statistics by
     callstack of Eva ([Eva_perf]), which record the duration of each call
     and of the calls that it makes;
   - the observers of the Safety part ({!Safety_part.on_result}), of the
     Reach part ({!Reach_part.on_result}) and of the results of the
     collector ({!Body_access.Result.on_result}), which run after the
     analysis of a body, apart from those registered as audited.

   Registration is the test: a client cannot be removed, apart from a daemon
   of [Async], and one registered after the production of an entry counts.
   The predicates of the parts are evaluated before ({!Cache_part.decide}),
   as those of the readers of the statement states: a hook that they
   register is seen here. *)
let unaudited_clients parts =
  Cache_part.unaudited_clients parts
  || Cvalue_callbacks.unaudited_hooks ()
  || Red_statuses.has_hooks ()
  || Property_status.has_add_or_update_hooks ()
  || Annotations.has_unaudited_hooks_on_change ()
  || Project.has_unaudited_clear_hooks ()
  || unaudited_status_dependents ()
  || Cil.has_inserted_cast_hook ()
  || Logic_env.has_hooks_on_logic_functions ()
  || Log.unaudited_clients ()
  || Messages.has_hooks ()
  || Safety_delivery.unaudited_subscribers ()
  || Hook.Opaque.has_unaudited_observers ()
  || Base.has_unaudited_observers ()
  || Origin.has_unaudited_observers ()
  || Async.has_daemons ()
  || Current_loc.has_hooks_on_change ()
  || Eva_perf.has_hooks_on_change ()
  || Safety_part.has_unaudited_observers ()
  || Reach_part.has_unaudited_observers ()
  || Body_access.Result.has_unaudited_observers ()

let cast : type a b. (a, b) Structure.eq -> a -> b = fun Structure.Eq x -> x
let cast_back : type a b. (a, b) Structure.eq -> b -> a =
  fun Structure.Eq x -> x

(* A fixture can omit the producing trace. Inspect the body itself for
   work that a hit would skip. The show directives are leaf displays
   handled directly by Transfer_stmt, and fixtures use them as visit
   markers. Dump directives can have ordered effects and are guarded. *)
let has_nested_call kf =
  let open Cil_types in
  let is_nested stmt =
    match stmt.skind with
    | Instr (Call (_, Var callee, _, _)) ->
      not (Ast_info.is_show_each_builtin callee.vname
           || Ast_info.is_domain_show_each_builtin callee.vname)
    | Instr (Call _ | Local_init (_, ConsInit _, _)) -> true
    | _ -> false
  in
  List.exists is_nested (Kernel_function.get_definition kf).sallstmts

module Lookup (Domain : sig
    type t
    val structure : t Abstract.Domain.structure
  end) = struct

  (* An equality between the states of the active domains and those of the
     cvalue domain, if the active domains are the cvalue domain alone. *)
  let cvalue_alone : (Domain.t, Cvalue_domain.State.t) Structure.eq option =
    match Domain.structure with
    | Abstract.Domain.Leaf (key, _) ->
      Structure.Key_Domain.eq_type key Cvalue_domain.State.key
    | _ -> None

  (* A hit delivers the Reach part of its entry: an entry without one is
     rejected at every call. An analysis of the body saves its states, and
     reaches points, when [save_results] holds for the function: a hit must
     then deliver the points reached. *)
  let missing_points stack entry =
    match Entry.reach entry with
    | None -> true
    | Some { points = None; _ } ->
      let kf = Callstack.top_kf stack in
      Function_calls.save_results (Kernel_function.get_definition kf)
    | Some { points = Some _; _ } -> false

  let admit stack nested_call entry (model, _) =
    let dependencies = Entry.dependencies entry in
    let used_functions =
      Option.fold ~none:[] ~some:(fun d -> d.Cache_entry.used_functions)
        dependencies
    in
    let would_skip_cleanup (f, _) =
      not (Kernel_function.equal f (Callstack.top_kf stack))
      && Kernel_function.is_definition f
    in
    if Body_access.recursion_conflict stack used_functions then Error `Recursion
    else if List.exists would_skip_cleanup used_functions
         && Builtins_malloc.has_automatic_bases ()
    then Error `Automatic_cleanup
    else if Builtins_watchpoint.active () then Error `Watchpoint
    else
      let check_dependencies d =
        let stale g =
          not (Widen_generation.equal g (Widen_generation.current ()))
        in
        if Option.fold ~none:false ~some:stale d.Cache_entry.hint_generation
        then Error `Hint_generation
        else if d.warn_categories <> Body_access.warn_categories ()
        then Error `Warn_categories
        else if not (Sweep_access.clear_input d.sweeps model) then Error `Sweep
        else Ok ()
      in
      match Option.fold ~none:(Ok ()) ~some:check_dependencies dependencies with
      | Error _ as error -> error
      | Ok () when missing_points stack entry -> Error `Missing_points
      | Ok () when Lazy.force nested_call -> Error `Nested_delivery
      | Ok () when Cache_producer.has_preconditions (Callstack.top_kf stack) ->
        Error `Preconditions
      | Ok () -> Ok ()

  let no_hit rejected =
    { rejected; hit = None; restoration = Cache_part.no_restoration }

  (* The predicates of the parts are client code: they are evaluated once,
     before the tests below, which see what they registered, and their
     answers serve the check of the parts and the restoration at a hit. *)
  let examine stack state candidates eq parts =
    let reject_all reason =
      no_hit (List.map (fun e -> Entry.id e, reason) candidates)
    in
    if consumer_enabled parts || stack.Callstack.thread <> Thread.main_id
    then reject_all `Consumer
    else if stop_at_nth_alarm () then reject_all `Stop_at_nth_alarm
    else if unaudited_clients parts then reject_all `Callback
    else if Self.analysis_in_progress ()
         && Self.ComputationState.get () <> Self.Computing
    then
      (* While an analysis runs, its results were cleared, as a change of
         an option of Eva does, or another analysis, started by a callback,
         ended: the options of the rest of the analysis may differ from
         those under which the entries were produced. A test that calls
         the lookup outside any analysis is not concerned. *)
      reject_all `Analysis_reset
    else
      let nested_call = lazy (has_nested_call (Callstack.top_kf stack)) in
      let result =
        Entry.find ~supplies:(Cache_part.supplies parts)
          ~admit:(admit stack nested_call) candidates (cast eq state)
      in
      let reject (e, reason) = Entry.id e, (reason :> rejection) in
      let hit (e, states) =
        e, List.map (fun (k, s) -> k, cast_back eq s) states
      in
      let restoration =
        match result.hit with
        | None -> Cache_part.no_restoration
        | Some (e, _) -> Cache_part.restoration parts (Entry.parts e)
      in
      { rejected = List.map reject result.rejected;
        hit = Option.map hit result.hit; restoration }

  let find stack state =
    match entries (Callstack.top_kf stack) with
    | [] -> no_hit []
    | candidates ->
      match cvalue_alone with
      | None ->
        no_hit (List.map (fun e -> Entry.id e, `Product) candidates)
      | Some eq -> examine stack state candidates eq (Cache_part.decide ())
end
