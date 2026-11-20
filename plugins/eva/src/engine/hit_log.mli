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

(** [body callstack ~producer ~complete ~entries ~points]: the open
    invocation on [callstack] analyzed its body. [entries] are the states
    that survive the preconditions; [points] are the states before and
    after each statement, or [None] if the results of the function are not
    recorded. [complete] is false when the analysis of the body stopped
    before its fixpoint: its points are then those computed so far. *)
val body:
  Callstack.t -> producer:int -> complete:bool -> entries:state list ->
  points:points Lazy.t option -> unit

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
    computed, as on one callstack. Returns [None] when the resolver
    declines, which it does whenever the records contain a memexec hit,
    except, after an interrupted analysis, at a point that no selected
    callstack reaches. Each answer is reported to {!Legacy_read_guard}.
    The answer is [Unknown_state] when:
    - the results are pending or not recorded;
    - the state of a selected callstack is unavailable, as on a callstack
      with an interrupted visit;
    - after an interrupted analysis, no selected callstack reaches the
      point, unless [callstacks] is supplied, at least one callstack is
      selected, and each selected callstack is classified. The analysis
      could have reached the point on a callstack it has not entered. *)
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
    callstack. After an interrupted analysis, the answer is [Unknown] when
    no selected callstack reaches the point, under the same conditions as
    in {!select}. Returns [None] when the records do not describe the
    current results, and when a negative answer could depend on a memexec
    hit. Each answer is reported to {!Legacy_read_guard}. *)
val reach:
  ?callstacks:Callstack.t list -> ?filter:(Callstack.t -> bool) ->
  Domain_store.control_point -> reach option

val pretty_answer: Format.formatter -> answer -> unit
val pretty_reach: Format.formatter -> reach -> unit

(** Prints the visits recorded on a callstack: their kind, their input, and
    the number of entries that survive the preconditions. *)
val pretty_visits: Format.formatter -> Callstack.t -> unit

(** Test control. When set, the resolver rebuilds each body visit from the
    first producer recorded for its function instead of its own. *)
val set_wrong_producer_control: bool -> unit
