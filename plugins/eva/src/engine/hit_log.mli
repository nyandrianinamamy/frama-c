(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Cache entries and hit log, recorded with option [-eva-hit-log], and the
    rule that answers the state requests from them once the analysis has
    ended.

    Each call analysed by its body records a cache entry, identified by the
    number that memexec gives to the call. Its Inner part holds, before and
    after each statement reached, the cvalue state projected on the blocks
    covered at that point: the blocks read or written on the paths from the
    start of the body to the point, as given by the inout plugin, and the
    blocks created by the call that exist at the point. The calls that use an
    entry, the one that computed it and its hits, form its key group: the hit
    log keeps, per entry, the join of their start states and of their
    body-entry states, overall and per callstack. The start state of a call
    is the state after the binding of its arguments; its body-entry state is
    what remains of it after the preconditions.

    The rule: the state at a point of a call is the Inner part of its entry
    at this point on the blocks it covers, and the body-entry state of the
    call on the other blocks. The state at the start of a function is the
    join of the start states of its calls, including the calls analysed by
    a specification or a builtin.

    Some functions are unavailable: every state request on them answers
    [`Top], as for a function whose results are not saved. A function is
    unavailable at every point, its start included, when it is called below
    a hit, that is while the cache entry of a hit was computed. Its body
    points only are unavailable when one of its calls has an unknown
    footprint, was interrupted, or is a recursive call analysed by its body.
    Every request is unavailable when the states of the cvalue domain are
    not saved, as with options [-eva-no-results] and
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

(** Records a call to a function, in any mode, in the set of functions
    called below the body being analysed. *)
val record_call: Cil_types.kernel_function -> unit

(** Records the start state of a call analysed by a specification or a
    builtin. *)
val record_start: Callstack.t -> Cvalue.Model.t -> unit

(** [analyse_body f] runs [f], the analysis of a body: the functions called
    meanwhile are recorded in the cache entry of this call. *)
val analyse_body: (unit -> 'a) -> 'a

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
    with its footprint, its start state, its body-entry state, and its states
    before and after each statement reached. Without footprint, as when the
    results of the call are not saved, its body points are unavailable. *)
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

(** [mark_interrupted callstack ~start] records the start state of a call
    interrupted before its end, and marks its function. *)
val mark_interrupted: Callstack.t -> start:Cvalue.Model.t -> unit

(** [analysis f] runs the analysis [f] of the current project. The rule
    answers the requests made after it, if the recording was on. *)
val analysis: (unit -> 'a) -> 'a

(** {2 The rule, after the analysis} *)

(** Whether the requests of the current project are answered by the rule:
    the recording was on and the analysis has ended. *)
val serving: unit -> bool

(** Whether the requests at a control point are answered: false if they are
    unavailable. *)
val available: Domain_store.control_point -> bool

(** The state at a control point, joined over all callstacks or for one. *)
val get_state:
  ?callstack:Callstack.t -> Domain_store.control_point ->
  Cvalue.Model.t or_top_bottom

(** The states at a control point of the callstacks that reach it. *)
val get_state_by_callstack:
  Domain_store.control_point ->
  (Callstack.t * Cvalue.Model.t) list or_top_bottom
