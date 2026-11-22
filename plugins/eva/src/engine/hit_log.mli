(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Cache entries and hit log, recorded with option [-eva-hit-log], and the
    rule that answers the state requests from them once the iteration of the
    analysis has ended, including the requests of the passes that Eva runs
    afterwards, such as the statuses of the properties and the summary.

    Each call analysed by its body records a cache entry, identified by the
    number that memexec gives to the call. Its Inner part holds, before and
    after each statement reached, the cvalue state projected on the blocks
    covered at that point: the blocks read or written on the paths from the
    start of the body to the point, as given by the inout plugin, and the
    blocks created by the call that exist at the point. The entry also keeps
    the calls made by the body, in any mode: for each, its call statement, the
    cache entry it used if any, and its start state projected on the blocks
    covered before the call statement, on the blocks that do not exist in the
    start state of the body, and on the blocks that the call binds or
    removes: the formals and locals of the callee, which can exist in the
    state of the caller under unrolled recursive calls, and the blocks of the
    start state of the body that the start state of the call does not have.

    The calls that use an entry form its key group: the call that computed
    it, its hits, and the calls below a hit that use it. The hit log keeps,
    per entry, the start state and the body-entry state of the call that
    computed it, and the join of the start states and of the body-entry states
    of its hits, overall and per callstack. The start state of a call is the
    state after the binding of its arguments; its body-entry state is what
    remains of it after the preconditions.

    The body of a hit does not run: the calls below a hit are not analysed.
    The start state of such a call is the start state stored in the entry of
    the hit, pasted on the body-entry state of the hit. Its preconditions are
    not evaluated: its body-entry state is its start state. These states are
    computed on request, through the entries of the callers, and memoised.

    The rule: the state at a point of a call is the Inner part of its entry
    at this point on the blocks it covers, and the body-entry state of the
    call on the other blocks. The state at the start of a function is the
    join of the start states of its calls, including the calls analysed by
    a specification or a builtin.

    The body points of a function are unavailable when one of its calls has
    an unknown footprint, was interrupted, or is a recursive call analysed by
    its body: every state request on them answers [`Top], as for a function
    whose results are not saved. Every request is unavailable when the states
    of the cvalue domain are not saved, as with options [-eva-no-results] and
    [-eva-no-results-domain cvalue].

    Only the cvalue domain is recorded. The records are saved with the
    project, and kept by its copies. *)

open Eval

(** Whether option [-eva-hit-log] is set. *)
val enabled: unit -> bool

(** Aborts the analysis if the recording is on and a domain other than
    cvalue is enabled. *)
val check_configuration: unit -> unit

(** {2 Recording, during the analysis} *)

(** Records the initial state of the analysis. *)
val record_initial_state: Callstack.t -> Cvalue.Model.t -> unit

(** [call callstack ~start f] runs [f], the analysis of the call on
    [callstack] in any mode, whose start state is [start]. The call is
    recorded among the calls made by the body that makes it, with the cache
    entry it uses. If [f] raises an exception, the call is interrupted: its
    start state is recorded, the points of the body of its function are
    unavailable, and the exception is raised again. *)
val call: Callstack.t -> start:Cvalue.Model.t -> (unit -> 'a) -> 'a

(** Records the start state of a call analysed by a specification or a
    builtin. *)
val record_start: Callstack.t -> Cvalue.Model.t -> unit

(** The memory read or written on the paths from the start of a body to the
    point before and to the point after each statement, as given by the inout
    plugin. *)
type footprint = Cil_types.stmt -> Memory_zone.t * Memory_zone.t

(** [footprint_of_call ~id hooks] runs [hooks], the hooks at the end of the
    call analysed by its body that computes the cache entry [id], and returns
    the footprint that the inout plugin gives meanwhile for this call, if
    any. The footprint is kept with the current project and this call: it is
    not lost to an analysis of another project started by the hooks, and is
    not kept after the hooks. *)
val footprint_of_call: id:int -> (unit -> unit) -> footprint option

(** [record_analysed_call ~id callstack ~footprint ~start ~body_entry ~before
    ~after] records the cache entry [id] computed by the call on [callstack],
    with its footprint, its start state, its body-entry state, its states
    before and after each statement reached, and the calls made by its body.
    Without footprint, as when the results of the call are not saved, its
    body points are unavailable. *)
val record_analysed_call:
  id:int -> Callstack.t -> footprint:footprint option ->
  start:Cvalue.Model.t -> body_entry:Cvalue.Model.t ->
  before:Cvalue.Model.t Cil_datatype.Stmt.Hashtbl.t Lazy.t ->
  after:Cvalue.Model.t Cil_datatype.Stmt.Hashtbl.t Lazy.t ->
  unit

(** [record_hit ~id callstack ~start ~body_entry] records a hit of the cache
    entry [id] on [callstack]. *)
val record_hit:
  id:int -> Callstack.t ->
  start:Cvalue.Model.t -> body_entry:Cvalue.Model.t -> unit

(** Marks a function of which a recursive call is analysed by its body. *)
val mark_unrolled_recursion: Cil_types.kernel_function -> unit

(** [analysis f] runs [f], the iteration of an analysis of the current
    project. The rule answers the requests made after it, if the recording
    was on. *)
val analysis: (unit -> 'a) -> 'a

(** {2 The rule, after the iteration} *)

(** Whether the requests of the current project are answered by the rule:
    the recording was on and the iteration of the analysis has ended. *)
val serving: unit -> bool

(** Whether the requests at a control point are answered: false if they are
    unavailable. *)
val available: Domain_store.control_point -> bool

(** The state at a control point, joined over all callstacks or for one.
    The answers joined over all callstacks are memoised: the records do not
    change once the iteration has ended. *)
val get_state:
  ?callstack:Callstack.t -> Domain_store.control_point ->
  Cvalue.Model.t or_top_bottom

(** The states at a control point of the callstacks that reach it. *)
val get_state_by_callstack:
  Domain_store.control_point ->
  (Callstack.t * Cvalue.Model.t) list or_top_bottom
