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
    number that memexec gives to the call. Except for a refused heap call,
    see below, its Inner part holds, before and after each statement
    reached, the cvalue state projected on the blocks covered at that point:
    the blocks read or written on the paths from the start of the body to
    the point, as given by the inout plugin, and the blocks created by the
    call that exist at the point. The entry also keeps
    the calls made by the body, in any mode: for each, its call statement, the
    cache entry it used if any, and its start state projected on the blocks
    covered before the call statement, on the blocks that do not exist in the
    start state of the body, and on the blocks that the call binds or
    removes: the formals and locals of the callee, which can exist in the
    state of the caller under unrolled recursive calls, and the blocks of the
    start state of the body that the start state of the call does not have.

    The calls that use an entry form its key group: the call that computed
    it, its hits, and the calls below a hit that use it. A hit uses its
    entry through a renaming of the allocated blocks, from the blocks of the
    call that computed the entry to its own, which memexec gives (see
    {!Mem_exec.renaming}): the identity unless memexec matched the call on
    its numbered form. The hit log keeps, per entry, the start state and the
    body-entry state of the call that computed it, and the join of the start
    states and of the body-entry states of its hits, overall and per
    callstack, each grouped by renaming. The start state of a call is the
    state after the binding of its arguments; its body-entry state is what
    remains of it after the preconditions.

    The body of a hit does not run: the calls below a hit are not analysed.
    The start state of such a call is the start state stored in the entry of
    the hit, renamed through the renaming of the hit, pasted on the
    body-entry state of the hit. Its preconditions are not evaluated: its
    body-entry state is its start state. The entry stores, with each call
    made by the body, the renaming through which this call used its own
    entry; below a hit, the call uses that entry through the composition of
    this renaming with the renaming of the hit. These states are
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
    at this point on the blocks it covers, renamed through the renaming of
    the call, and the body-entry state of the call on the other blocks. A
    state joined over several calls is the join of the rule applied once per
    group of calls with the same renaming, to the join of their body-entry
    states; the point is unavailable to a group whose renaming does not
    rename each allocated block of the point to a distinct block. The state
    at the start of a function is the join of the start states of its
    calls, including the calls analysed by a specification or a builtin.

    A heap call is a call analysed by its body that receives a heap effect
    (see {!Heap_effects}): an effect emitted during its analysis, in its body
    or in a call nested in it, or by the automatic release at the end of a
    call made by its body. The builtins of [malloc], [calloc], [realloc],
    [reallocarray], [alloca], [free], and of the allocation and release of
    variable-length arrays emit them, and so does the widening of the
    memory, when it raises the validity of a weak block. Every caller of a
    heap call analysed by its body, up to the entry point, is a heap call. A
    call that reads or writes an allocated block and receives no heap effect
    is not a heap call.

    Memexec stores a call that frees, a heap call whose heap effects are
    removals and sweeps only, and a call that allocates by [malloc] (#127),
    [calloc], [realloc], [reallocarray] (#129), [alloca] or a
    variable-length array (#130) under the policy [by_stack], if it is not
    refused and its entry holds an Inner part, see [storage]. It stores no
    other heap call. The entry of a call ends at the exit of its body: the
    automatic release at the end of the call runs after the entry is stored,
    and after a hit, on the blocks that the table of the allocated blocks
    gives to the callstack of the call, and its effects go to the caller. A
    hit registers each block it creates for the callstack of its
    allocation without the call of the builtin, which can be a call nested
    below the hit, see {!Builtins_malloc.replay_creation}. The entry of a
    heap call keeps the calls made by the body, projected as above and on
    the blocks covered by the heap effects before the call statement: a hit
    on the entry of a call that frees has calls below it. A hit on the entry
    of a heap call passes to the call that makes it the heap effects of the
    analysed call of the entry, in their order, and its sweeps from the
    start of its body to its return, through the renaming of the hit (#128):
    the call that makes the hit is a heap call, stored by memexec as if the
    call it made were analysed, see [record_hit].

    The Inner part of a heap call also covers the blocks that its heap
    effects allocate, mutate or remove, from the point where the effect
    happens on: after the statement of the call that receives the effect or
    whose automatic release makes it, and from the point before the loop
    whose widening makes it. After a call statement, it also covers the
    variables that a recursive call, made there or in a call nested there,
    withdraws from the state: the recursive call puts them back at its end
    as they were before it, unswept by its releases. The paths from the
    start of the body are those of its analysis: an edge of the automaton of
    the body through which the analysis propagated no state is on no path. A
    covered block that the Inner part does not bind is removed at the point:
    this is the removal mask.

    Each point also holds a sweep map: the blocks swept on every path from
    the start of the body to the point, and those swept on some path only.
    A block is swept when a release turns the pointers to it into escaping
    addresses. The map keeps the blocks that the body-entry state does not
    bind: this state can point to them, as a recursive call puts back
    unswept the variables that it withdraws from the state. At a call
    statement, the sweeps of each evaluation of the call that returns are
    followed by those of the automatic release at its end, and the
    evaluations are merged: a block swept on every path of each of them is
    swept on every path, and a block swept in some of them only, or on some
    path only, is swept on some path only. The sweeps of a [free] on several
    blocks or on a weak block, which joins the pointers with escaping
    addresses, and of a builtin that returns several states, as [realloc]
    when it may fail, are on some path only. The paths are joined
    at each vertex of the automaton, while the states that reach it can
    stay apart: a block that the body-entry state binds, swept on some path
    only, that the state at the point does not bind, is swept on every
    path, as the state at the point binds every block that one of the
    states that reach it binds, and only a release that sweeps the block on
    its path removes it. The same holds for the sweeps of the call at its
    return, which its caller receives. A block that the state at the point
    binds, or that the body-entry state does not bind, keeps its class. A
    request at a point of a heap call is answered by the rule, applied to
    the body-entry state of the call swept by the sweep map of the point:
    the pointers to a block swept on every path become escaping addresses,
    and those to a block swept on some path only are joined with escaping
    addresses.

    A heap call is refused in threaded mode, when it or a call nested in it
    calls the builtin of [Frama_C_check_leak], which reads every allocated
    block, when it receives in its body an effect whose statement is not
    known, and when its footprint contains an unknown set of blocks, see
    below. The entry of a refused heap call holds no Inner part: it holds
    the full cvalue state before and after each statement reached, the
    states that the analysis of the body computes and that the legacy store
    saves, taken when the analysis of the body ends. A request at a point of
    a refused heap call is answered by these full states; the rule is not
    applied. The statistic [hit-log-heap-calls] counts the heap calls, and
    [hit-log-full-states] those of them whose entries hold full states.

    With memexec, the hits that memexec no longer makes are counted per
    function: the statistic [hit-log-lost-hits] counts the calls that it
    would have reused if it stored the heap calls that it does not store,
    with their real blocks, not through a renaming, except those made during
    the analysis of such a call, which would have been below a hit:
    [hit-log-lost-hits-below] counts these. A call is counted in one of the
    two only.

    A heap call for which InOut gives no footprint, as when the results of
    its function are not saved, has no Inner part and no full states: its
    body points are unavailable. A heap call whose footprint contains an
    unknown set of blocks keeps its full states, which need no footprint,
    and its body points are answered by them.

    The body points of a function are unavailable when one of its calls has
    an unknown footprint (for a heap call, no footprint at all), was
    interrupted, or is a recursive call analysed by its body: every state
    request on them answers [`Top], as for a function whose results are not
    saved. On the callstack of a call below a hit that crosses a recursion,
    the start and the points of the body of the call are unavailable: the
    state on this callstack is [Cvalue.Model.top], and so is every joined or
    filtered state that includes it; the other callstacks are answered.
    Every request is unavailable when the states of the cvalue domain are
    not saved, as with options [-eva-no-results] and
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

(** [record_analysed_call ~id callstack ~automaton ~fired ~footprint ~start
    ~body_entry ~before ~after] records the cache entry [id] computed by the
    call on [callstack], with its footprint, its start state, its body-entry
    state, its states before and after each statement reached, and the calls
    made by its body. [automaton] is the automaton of the body, and [fired]
    tells the edges through which its analysis propagated a state. For a
    heap call, the Inner part, and the start states of the calls made by the
    body, also cover the blocks of its heap effects, with the sweep map,
    computed on the paths of the edges [fired]. A refused heap call, with a
    footprint, keeps its states before and after each statement whole, and
    no call made by the body. Without footprint, as when the results of
    the call are not saved, its body points are unavailable. *)
val record_analysed_call:
  id:int -> Callstack.t ->
  automaton:Eva_automata.automaton -> fired:(Eva_automata.edge -> bool) ->
  footprint:footprint option ->
  start:Cvalue.Model.t -> body_entry:Cvalue.Model.t ->
  before:Cvalue.Model.t Cil_datatype.Stmt.Hashtbl.t Lazy.t ->
  after:Cvalue.Model.t Cil_datatype.Stmt.Hashtbl.t Lazy.t ->
  unit

(** A renaming of the allocated blocks of a cache entry: pairs of blocks,
    from the blocks of the analysed call of the entry to those of a call
    that uses it, see {!Mem_exec.renaming}. The empty list is the
    identity. *)
type renaming = (Base.t * Base.t) list

(** [record_mentioned mentioned] records, for the cache entry computed by
    the innermost [call], the allocated blocks that memexec numbered when it
    stored the entry, as {!Mem_exec.Make.store_computed_call} returns them.
    Below a hit, a call that used this entry by identity uses it through the
    renaming of the hit restricted to these blocks. Nothing is recorded for
    [None]: the renaming of the hit is then used whole. *)
val record_mentioned: Base.t list option -> unit

(** [record_hit ~id ~renaming callstack ~start ~body_entry] records a hit of
    the cache entry [id] on [callstack], through [renaming]. If [id] is the
    entry of a heap call, the hit receives the heap effects of the analysed
    call of the entry and its sweeps from the start of its body to its
    return, renamed through [renaming], with the stack of each allocation
    moved from the callstack of the analysed call to [callstack], and the
    variables that the recursive calls nested in the analysed call withdrew:
    the innermost [call] passes them to the caller. Fails if the entry of [id]
    holds full states, which memexec does not store, if the effects of the
    entry of a heap call were not kept, or if they name a block that
    [renaming], when it is not the identity, does not map. *)
val record_hit:
  id:int -> renaming:renaming -> Callstack.t ->
  start:Cvalue.Model.t -> body_entry:Cvalue.Model.t -> unit

(** [builtin_outputs n] records that the builtin whose analysis the innermost
    [call] runs returns [n] states. *)
val builtin_outputs: int -> unit

(** How memexec stores the call on [callstack] analysed by its body whose
    analysis the innermost [call] runs, once [record_analysed_call] has
    recorded it:
    - [Plain]: the call is not a heap call; memexec stores it as without
      heap effects;
    - [Heap heap]: a heap call, not refused, whose entry holds an Inner
      part, see {!Mem_exec.heap}, whose heap effects are removals, sweeps,
      and allocations by [malloc] (#127), [calloc], [realloc],
      [reallocarray] (#129), [alloca] and the allocation of variable-length
      arrays (#130) under the policy [by_stack] at sites without
      annotation, each with the resize of the block it reuses, and whose
      stack, without the allocation wrappers, ends below the call;
    - [Refused]: any other heap call, among them a call with another
      allocation or with a validity mutation by the widening of a loop, and
      any call whose entry, or the entry of a call nested in it, holds full
      states.
      Memexec does not store it. The allocation builtins let memexec store
      no call that allocates under another policy or at an annotated site,
      except the policy [imprecise] once its single block exists, which this
      refuses. *)
type storage =
  | Plain
  | Heap of Mem_exec.heap
  | Refused

val storage: callstack:Callstack.t -> storage

(** [lost_hit kf f] runs [f], the analysis of a call to [kf] that memexec
    would have reused if it stored the heap calls that it does not store,
    and counts it as a hit not made. *)
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

(** [recursive_call callstack recursion]: the call on [callstack], about to
    be analysed, is a recursive call, which withdraws variables from the
    state and puts them back at its end, see [recursion]. The heap calls in
    which it is nested cover these variables after their call statement that
    leads to it. *)
val recursive_call: Callstack.t -> recursion -> unit

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

(** {2 For the tests of the hit log} *)

(** The Inner part of a cache entry at a point: the blocks it covers, the
    state projected on them, and the sweep map, made of the blocks swept on
    every path from the start of the body to the point and of those swept on
    some path only. *)
type inner_view = {
  covered: Base.Hptset.t;
  inner: Cvalue.Model.t;
  swept_every: Base.Hptset.t;
  swept_some: Base.Hptset.t;
}

(** What a cache entry holds at a point. *)
type point_view =
  | Full_states (** The entry holds full states. *)
  | No_point
  (** The entry holds no Inner part, its footprint being unknown, or does
      not reach the point, or does not exist. *)
  | Inner of inner_view

(** [point_view ~id control_point] is what the cache entry [id] holds at
    [control_point], a point before or after a statement of the body of its
    function. *)
val point_view: id:int -> Domain_store.control_point -> point_view

(** [rule ~id ~renaming ~body_entry control_point] is the state that the
    rule gives at [control_point], a point before or after a statement of the
    body of the function of the cache entry [id], to a call that uses this
    entry through [renaming], the identity by default, and whose body-entry
    state is [body_entry]. None if the entry holds no Inner part at this
    point, see {!point_view}, or if [renaming] does not rename each
    allocated block of the point to a distinct block. *)
val rule:
  id:int -> ?renaming:renaming -> body_entry:Cvalue.Model.t ->
  Domain_store.control_point -> Cvalue.Model.t option

(** [members ~id] are the members of the cache entry [id] whose body did not
    run, its hits and the calls below a hit that use it, grouped by
    callstack and by the renaming through which they use the entry, with
    their body-entry states joined, in the order of the callstacks. *)
val members: id:int -> (Callstack.t * renaming * Cvalue.Model.t) list
