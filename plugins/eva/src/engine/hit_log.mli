(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Hit log and result resolver (prototype).

    During an analysis, Eva records here the initialized globals and each
    invocation of a function: its callstack, its input after the binding of
    the arguments to the formals, and how it was interpreted. The analysis
    of a body also records its producer: the entries that survive the
    preconditions, possibly none, and the normalized states before and
    after each statement, the same states that the collection hooks of
    {!Cvalue_callbacks} receive. A memexec hit records the producer of the
    cache entry it uses.

    {!classify} answers a request at a control point on one callstack from
    these records, without reading the legacy result store. It rebuilds
    the state of each visit on the callstack, then joins the visits in the
    order of the analysis. It tells a reached point from an unreachable
    one, from a body that no visit analyzed, and from a result that is
    unavailable. A point is unreachable only on positive evidence: a visit
    whose analysis completed, whose points are recorded, and which has no
    state at the point, in an analysis that completed. {!resolve} converts
    the answer to the public one of the legacy store. {!reach} tells
    whether any selected callstack reaches a point. {!select} enumerates
    the selected callstacks that reach a point, apart from the state of
    the selection, which is unknown as soon as one selected callstack may
    contribute an unavailable state. {!resolve_consolidated} joins the
    callstacks. The requests on several callstacks, or on none, keep their
    own aggregation on top of these states.

    The records describe the current results when the cvalue domain runs
    alone, without multithread analysis, and with [-eva-hit-log]. With
    [-eva-no-results] or [-eva-no-results-domain cvalue], they record the
    invocations and how they were interpreted, and every state is
    unavailable. The resolver declines a request on a memexec hit, or below
    one, whose states it cannot rebuild yet, and the requests on several
    callstacks or none that depend on a hit. When it declines,
    the request reads the legacy store. The records are not saved with the
    project, and clearing the results of Eva invalidates them. *)

type state = Cvalue_domain.State.t

(** How Eva interpreted an invocation. *)
type kind =
  | Body of int
  (** Its body was analyzed; this invocation is the producer of this id. *)
  | Hit of int
  (** A memexec hit on the cache entry of the producer of this id. *)
  | Spec
  (** Its specification was used; the body was not analyzed. *)
  | Builtin of string
  (** The builtin of this name was used; the body was not analyzed. *)
  | Unresolved
  (** Nothing is recorded yet: the analysis has not interpreted the call,
      or stopped first. *)

(** {2 Recording} *)

(** [start ~exact ~states] starts the records of a new analysis. Nothing is
    recorded unless [exact]. States are unavailable unless [states]. *)
val start: exact:bool -> states:bool -> unit

(** Marks the records as complete, once the analysis has completed. *)
val seal: unit -> unit

(** Marks the records as interrupted, when the analysis stops early. The
    invocations still open at that time are interrupted. *)
val interrupt: unit -> unit

(** Whether the current analysis records. *)
val recording: unit -> bool

(** [initial callstack state]: the initialized globals, before the binding
    of the formals of the entry point. *)
val initial: Callstack.t -> state -> unit

(** [enter callstack input] opens an invocation, whose input is the state
    after the binding of the arguments to the formals. *)
val enter: Callstack.t -> state -> unit

(** [leave callstack] closes the innermost open invocation. *)
val leave: Callstack.t -> unit

(** [hit callstack ~producer]: the open invocation on [callstack] is a
    memexec hit. *)
val hit: Callstack.t -> producer:int -> unit

(** [interpreted callstack kind]: the open invocation on [callstack] is
    interpreted by its specification or by a builtin. *)
val interpreted: Callstack.t -> [ `Spec | `Builtin of string ] -> unit

type points = {
  before: state Cil_datatype.Stmt.Hashtbl.t;
  after: state Cil_datatype.Stmt.Hashtbl.t;
}

(** The branches of each conditional that the analysis of a body took:
    whether the then and the else branches of the statement are
    fireable. *)
type guards = (bool * bool) Cil_datatype.Stmt.Hashtbl.t

(** [body callstack ~producer ~complete ~entries ~points ~guards]: the open
    invocation on [callstack] analyzed its body. [entries] are the states
    that survive the preconditions; [points] are the states before and
    after each statement, or [None] if the results of the function are not
    recorded. [guards] are recorded whatever the results recorded.
    [complete] is false when the analysis of the body stopped before its
    fixpoint: its points and guards are then those computed so far. *)
val body:
  Callstack.t -> producer:int -> complete:bool -> entries:state list ->
  points:points Lazy.t option -> guards:guards -> unit

(** {2 Registration}

    Eva still writes its legacy tables during the analysis: the states of
    each control point on each callstack, the analysis status and the
    callers of each function, and the fireable branches of each
    conditional. The requests that the resolver declines read them, and a
    saved project keeps them. Each write merges a new fact with the one
    already registered. While the hit log records, the functions below give
    the fact already registered from the records, so that the writers of
    the legacy tables never read them. Each returns [None] when the hit log
    does not record: the writer then reads the legacy table. Each answer is
    reported to {!Legacy_read_guard}. *)

(** [registered ~callstack point] is the state that the earlier visits on
    [callstack] registered at [point], before the registration of the
    latest one: the join of their inputs at the start of the function,
    of the states of their bodies at a statement, in the order of the
    analysis; [Some None] when there is none, or when the states are not
    recorded, and the legacy store records none either. Not for the
    initial state, which is registered once. *)
val registered:
  callstack:Callstack.t -> Domain_store.control_point -> state option option

(** [target callstack status] records that the analysis chose to interpret
    the open invocation on [callstack] with [status]. Returns the merged
    status of its function, and its callers, including this call. *)
val target:
  Callstack.t -> Function_calls.analysis_status ->
  (Function_calls.analysis_status
   * Cil_datatype.Stmt.Set.t Kernel_function.Map.t) option

(** [fire stmt (then_, else_)] records that the analysis took the then
    branch of the conditional [stmt] if [then_], its else branch if [else_].
    Returns whether some analysis took each branch so far. *)
val fire: Cil_types.stmt -> bool * bool -> (bool * bool) option

(** {2 Resolver} *)

(** Why the records cannot give the state at a point. *)
type unavailable =
  | Pending
  (** The analysis is running: no result is available yet. *)
  | Interrupted
  (** The analysis stopped before its end, and the point is not reached by
      what it computed. Later visits, or the rest of an interrupted one,
      could reach it. *)
  | Not_recorded
  (** The states are deliberately not recorded: [-eva-no-results],
      [-eva-no-results-domain cvalue] or [-eva-no-results-function]. *)

(** The answer at a control point on one callstack. *)
type answer =
  | Reached of state
  (** The join of the states of the visits that reach the point. *)
  | Unreachable
  (** Every visit analyzed its body to completion, and none reaches the
      point; or no invocation of the function exists on the callstack. *)
  | Not_analyzed
  (** The visits on the callstack interpret the function by its
      specification or a builtin: the call is reached, the statements of
      its body are not analyzed. *)
  | Unavailable of unavailable
  (** The records do not tell. One unavailable visit makes the whole
      callstack unavailable. *)

(** Whether the records describe the current results. The resolver then
    answers every request on them, except those it declines. *)
val describes_results: unit -> bool

(** The initialized globals that {!initial} recorded, before the binding of
    the formals of the entry point, as the logic label Init reads them. The
    state is final once recorded, and is answered while the analysis runs:
    [`Bottom] before it is recorded, [`Top] when the states are not
    recorded. Returns [None] when the records do not describe the current
    results. Each answer is reported to {!Legacy_read_guard}. *)
val initial_state: unit -> state Lattice_bounds.or_top_bottom option

(** [classify ~callstack point] answers from the records. Returns [None]
    when the records do not describe the current results, and on the
    points of a memexec hit and of the callstacks below one, whose states
    are not rebuilt yet. *)
val classify:
  callstack:Callstack.t -> Domain_store.control_point -> answer option

(** [resolve ~callstack point] is {!classify} converted to the public
    answer of the legacy store, as [Eva.Results] reports it. The legacy
    store answers [`Bottom] at the points that an interrupted analysis did
    not reach; the resolver answers [`Top]. Each answer is reported to
    {!Legacy_read_guard}.
    - [Reached s] is [`Value s];
    - [Unreachable] is [`Bottom];
    - [Not_analyzed] is [`Bottom], the response that [Eva.Analysis.status]
      declares for a function interpreted by its specification or a
      builtin;
    - [Unavailable _] is [`Top]. *)
val resolve:
  callstack:Callstack.t -> Domain_store.control_point ->
  state Lattice_bounds.or_top_bottom option

(** The answer at a control point on a selection of callstacks. The
    callstacks that reach the point are enumerated apart from the state of
    the selection: a callstack reaches the point when one of its visits
    does, even if the state of another visit is unavailable. *)
type 'a selection =
  | Known of (Callstack.t * 'a) list
  (** The state of each selected callstack is known: the callstacks that
      reach the point, with their state, in the order in which the legacy
      store enumerates them. The other selected callstacks do not reach the
      point. *)
  | Unknown_state of Callstack.t list
  (** The state of some selected callstack, or of a callstack that the
      analysis has not entered, is unavailable. The list holds the
      selected callstacks that reach the point, in the order of the legacy
      store; it is empty when the results are pending or not recorded. *)

(** [select ?callstacks ~filter point] answers at [point] on [callstacks]
    that satisfy [filter]. [callstacks] defaults to the callstacks of the
    function of [point] in the records. The state of each callstack is
    rebuilt as {!resolve} does. After an interrupted analysis, the state of
    a callstack that reaches the point is the one that the analysis
    computed, as on one callstack. Each answer is reported to
    {!Legacy_read_guard}.

    When [callstacks] is supplied and [filter] rejects each of them, or
    [callstacks] is empty, the selection is empty: the answer is
    [Known []] whenever the records describe the current results, whatever
    the completion of the analysis and the records of the rejected
    callstacks.

    Otherwise, returns [None] when the resolver declines, which it does
    whenever the records contain a memexec hit, except, after an
    interrupted analysis, at a point that no selected callstack reaches.
    The answer is [Unknown_state] when:
    - the results are pending or not recorded;
    - the state of a selected callstack is unavailable, as on a callstack
      with an interrupted visit;
    - after an interrupted analysis, no selected callstack reaches the
      point, unless [callstacks] is supplied and each selected callstack is
      classified. The analysis could have reached the point on a callstack
      it has not entered. *)
val select:
  ?callstacks:Callstack.t list -> filter:(Callstack.t -> bool) ->
  Domain_store.control_point -> state selection option

(** [resolve_by_callstack point] is {!select} on every callstack, converted
    to the answer of the legacy store: [`Top] for [Unknown_state], [`Bottom] for
    [Known []]. *)
val resolve_by_callstack:
  Domain_store.control_point ->
  (Callstack.t * state) list Lattice_bounds.or_top_bottom option

(** [resolve_consolidated point] joins the states of {!select} on every
    callstack, as the legacy consolidation does: [`Top] for
    [Unknown_state].
    Returns [None] when the resolver declines. *)
val resolve_consolidated:
  Domain_store.control_point -> state Lattice_bounds.or_top_bottom option

(** Whether the analysis reached a point on some selected callstack. *)
type reach =
  | Reaching
  | Not_reaching
  (** Every selected callstack is [Unreachable] or [Not_analyzed]. *)
  | Unknown of unavailable

(** [reach ?callstacks ?filter point] tells whether [point] is reached on
    one of [callstacks] that satisfies [filter]. [callstacks] defaults to
    the callstacks of the function of [point] in the records. A point
    reached on a callstack is reached whatever the other visits on that
    callstack. When [callstacks] is supplied and [filter] rejects each of
    them, the answer is [Not_reaching], as the selection is empty in
    {!select}. After an interrupted analysis, the answer is [Unknown] when
    no selected callstack reaches the point, under the same conditions as
    in {!select}. Returns [None] when the records do not describe the
    current results, and when a negative answer could depend on a memexec
    hit. Each answer is reported to {!Legacy_read_guard}. *)
val reach:
  ?callstacks:Callstack.t list -> ?filter:(Callstack.t -> bool) ->
  Domain_store.control_point -> reach option

(** {2 Semantic facts}

    Facts of the analysis that the states do not give. Each answer is
    reported to {!Legacy_read_guard}. The call relations, which the hit log
    derives from the callstacks of its invocations, answer the readers of
    {!Function_calls}. *)

(** [condition_truth_value stmt]: whether some analysis of the body of the
    function of [stmt] took the then branch, and the else branch, of the
    conditional [stmt], as [Eva.Results.condition_truth_value] reports it.
    The union of the guards of the producers of the invocations of the
    function. Returns [None] while the analysis runs, since the legacy
    table is updated on each transition while a producer records its
    guards at its end, when the records do not describe the current
    results, and when they contain a memexec hit. *)
val condition_truth_value: Cil_types.stmt -> (bool * bool) option

(** Whether the analysis has ended, completed or interrupted, as
    [Eva.Analysis.is_computed] reports it. Returns [None] when the records
    do not describe the current results. *)
val computed: unit -> bool option

(** The computation state, as [Eva.Analysis.current_computation_state]
    reports it: computing while the records are recorded, computed once
    they are sealed, aborted once interrupted, and computed once restored
    from a snapshot, as [Eva_results.set_results] sets it. Returns [None]
    when the records do not describe the current results. *)
val computation_state: unit -> Self.computation_state option

(** [analyzed kf]: whether some invocation of [kf] analyzed its body, or
    reused the analysis of its body by a memexec hit, in a completed
    analysis. The analysis status of [kf] then tells [Analyzed]. Returns
    [None] before the analysis has completed, when the records do not
    describe the current results, and when an invocation of [kf] is
    unresolved. *)
val analyzed: Kernel_function.t -> bool option

(** [status kf] is the analysis status of [kf] as the status table
    registers it, [Unreachable] when no call to [kf] is registered, and
    whether the analysis has ended, as {!computed}. The statuses of the
    calls to a function are merged in the order of the calls, with the
    merge of the status table. Answers while the analysis runs. Returns
    [None] when the records do not describe the current results. The
    answer is reported to {!Legacy_read_guard}. *)
val status: Kernel_function.t -> (Function_calls.analysis_status * bool) option

(** The analysis status and the callers of each function that the analysis
    called, as the status table and the table of call relations register
    them, once the analysis has ended. Returns [None] when the records do
    not describe the current results, before the analysis has ended, and
    when the records contain a memexec hit. Each answer is reported to
    {!Legacy_read_guard}. *)
val calls: unit -> Function_calls.t option

(** {2 Snapshots} *)

(** [stored_states point] is the state of each callstack that reaches
    [point], in the order of the legacy store, rebuilt from the records
    once the analysis has ended. It is what the legacy store records at
    [point], and is empty where the states are not recorded. After an
    interruption, where the state of a callstack is unavailable to the
    requests, it is the join of the states that the visits on each
    callstack registered, including those of an interrupted body. Returns
    [None] when the resolver declines, and when the state of a callstack
    of a completed analysis is unavailable. Each answer is reported to
    {!Legacy_read_guard}. *)
val stored_states:
  Domain_store.control_point -> (Callstack.t * state) list option

(** The records of the results of an ended analysis. *)
type snapshot

(** The records of the current results, if they describe them and the
    analysis has ended. *)
val snapshot: unit -> snapshot option

(** [restore snapshot] makes [snapshot] the records of the current results:
    the resolver answers each request as it did on the results that
    [snapshot] describes. Clearing the results of Eva invalidates them:
    restore the snapshot after the changes that clear the results. *)
val restore: snapshot -> unit

val pretty_answer: Format.formatter -> answer -> unit
val pretty_reach: Format.formatter -> reach -> unit

(** Prints the visits recorded on a callstack: their kind, their input, and
    the number of entries that survive the preconditions. *)
val pretty_visits: Format.formatter -> Callstack.t -> unit

(** Test control. When set, the resolver rebuilds each body visit from the
    first producer recorded for its function instead of its own. *)
val set_wrong_producer_control: bool -> unit

(** Test control. When set, the records describe no result: every request
    reads the legacy store, as written during the analysis. The
    registration of the hit log is unchanged. *)
val set_decline_control: bool -> unit

(** Test control. When set, {!calls} answers that every function is
    unreachable, without caller. *)
val set_calls_perturbation_control: bool -> unit
