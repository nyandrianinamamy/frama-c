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
    number that memexec gives to the call. Except for a heap call, see
    below, its Inner part holds, before and
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
    A call below a hit crosses a recursion when it is a recursive call that
    renames variables, analysed by its body or by its specification, or is
    made below such a call. A recursive call renames the variables of the
    outer call of its function whose address is taken or that an argument of
    the call copies, and rewrites the pointers to them, according to its
    depth on the callstack; the stored start state does not replay this
    renaming. A recursive call that renames no variable only removes the
    variables of the outer call, as the stored start state does. The states
    of a call that crosses a recursion are not rebuilt.

    The rule: the state at a point of a call is the Inner part of its entry
    at this point on the blocks it covers, and the body-entry state of the
    call on the other blocks. The state at the start of a function is the
    join of the start states of its calls, including the calls analysed by
    a specification or a builtin.

    A heap call is a call analysed by its body that receives a heap effect
    (see {!Heap_effects}): an effect emitted during its analysis, in its body
    or in a call nested in it, or by the automatic release at the end of a
    call made by its body. The builtins of [malloc], [calloc], [realloc],
    [reallocarray], [alloca], [free], and of the allocation and release of
    variable-length arrays emit them, and so does the widening of the
    memory, when it raises the validity of a weak block. Every caller of a
    heap call, up to the entry point, is a heap call. The entry of a heap
    call holds no Inner part: it holds the full cvalue state before and after each statement reached, the states that
    the analysis of the body computes and that the legacy store saves, taken
    when the analysis of the body ends. A request at a point of a heap call
    is answered by these full states; the rule is not applied. Memexec does
    not store a heap call: no hit, and thus no call below a hit, uses the
    entry of a heap call, and the entry does not keep the calls made by the
    body. A call that reads or writes an allocated block and receives no
    heap effect is not a heap call. With memexec, the hits that memexec
    no longer makes are counted per function: the statistic
    [hit-log-lost-hits] counts the calls that it would have reused if it
    stored the heap calls, except those made during the analysis of such a
    call, which would have been below a hit: [hit-log-lost-hits-below]
    counts these. A call is counted in one of the two only. The statistic
    [hit-log-heap-calls] counts the heap calls.

    A heap call for which InOut gives no footprint, as when the results of
    its function are not saved, has no full states: its body points are
    unavailable. A heap call whose footprint contains an unknown set of
    blocks keeps its full states, which need no footprint, and its body
    points are answered by them.

    The body points of a function are unavailable when one of its calls has
    an unknown footprint (for a heap call, no footprint at all), was interrupted, or is a recursive call analysed by
    its body: every state request on them answers [`Top], as for a function
    whose results are not saved. On the callstack of a call below a hit that
    crosses a recursion, the start and the points of the body of the call
    are unavailable: the state on this callstack is [Cvalue.Model.top], and
    so is every joined or filtered state that includes it; the other
    callstacks are answered. Every request is unavailable when the states
    of the cvalue domain are not saved, as with options [-eva-no-results] and
    [-eva-no-results-domain cvalue]. The initial state is unavailable when
    the initialization of the globals fails and the analysis does not start,
    as without recording.

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
    For a heap call, the states before and after each statement are kept
    whole, and the calls made by the body are not kept. Without footprint,
    as when the results of the call are not saved, its body points are
    unavailable. *)
val record_analysed_call:
  id:int -> Callstack.t -> footprint:footprint option ->
  start:Cvalue.Model.t -> body_entry:Cvalue.Model.t ->
  before:Cvalue.Model.t Cil_datatype.Stmt.Hashtbl.t Lazy.t ->
  after:Cvalue.Model.t Cil_datatype.Stmt.Hashtbl.t Lazy.t ->
  unit

(** [record_hit ~id callstack ~start ~body_entry] records a hit of the cache
    entry [id] on [callstack]. Fails if [id] is the entry of a heap call. *)
val record_hit:
  id:int -> Callstack.t ->
  start:Cvalue.Model.t -> body_entry:Cvalue.Model.t -> unit

(** Whether the call whose analysis the innermost [call] runs is a heap call
    so far: it has received a heap effect. For a call analysed by its body,
    the answer is final once the analysis of the body has ended. False when
    the recording is off. *)
val heap_call: unit -> bool

(** [lost_hit kf f] runs [f], the analysis of a call to [kf] that memexec
    would have reused if it stored the heap calls, and counts it as a hit not
    made. *)
val lost_hit: Cil_types.kernel_function -> (unit -> 'a) -> 'a

(** The heap effects that a call received while it was analysed, see
    {!Heap_effects}: those emitted in its body, and those that the calls it
    makes received, including the automatic release at the end of each of
    these calls. *)
type effects

(** [iter_effects f effects] applies [f point callee e] to each effect [e] of
    [effects], in the order of emission. [point] is the statement of the
    function of the call where [e] happens, if known, and [callee] is the
    function called at [point] whose analysis received [e], if any. *)
val iter_effects:
  (Cil_types.stmt option -> Cil_types.kernel_function option ->
   Heap_effects.t -> unit) ->
  effects -> unit

(** [register_effects_hook f] makes [call] apply [f callstack effects] when a
    call on [callstack] ends, whatever its mode, with the heap effects it
    received. With the recording only. *)
val register_effects_hook: (Callstack.t -> effects -> unit) -> unit

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
    The answers joined over all callstacks, and those for one callstack
    before and after a statement, are memoised: the records do not change
    once the iteration has ended. *)
val get_state:
  ?callstack:Callstack.t -> Domain_store.control_point ->
  Cvalue.Model.t or_top_bottom

(** The states at a control point of the callstacks that reach it. The
    answers before and after a statement are memoised. *)
val get_state_by_callstack:
  Domain_store.control_point ->
  (Callstack.t * Cvalue.Model.t) list or_top_bottom
