(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Dynamic allocation related builtins.
    Most functionality is exported as builtins. *)

val fold_dynamic_bases: (Base.t -> Callstack.t -> 'a -> 'a) -> 'a -> 'a
(** [fold_dynamic_bases f init] folds [f] to each dynamically allocated base,
    with initial accumulator [init].
    Note that this also includes bases created by [alloca] and [VLAs]. *)

val alloc_size_ok: Cvalue.V.t -> Alarmset.status
(* [alloc_size_ok size] checks that [size] represents a valid allocation
   size w.r.t. the total address space. [True] means that the requested size is
   small enough, [False] that the allocation is guaranteed to fail (because
   the size is always greater than SIZE_MAX). *)

val free_automatic_bases: Callstack.t -> Cvalue.Model.t -> Cvalue.Model.t
(** Performs the equivalent of [free] for each location that was allocated via
    [alloca()] in the current function (as per [Eva_utils.call_stack ()]).
    This function must be called during finalization of a function call.
    With option [-eva-hit-log], the removals and the sweeps are emitted as
    heap effects at the statement of the call, the top call site of the
    callstack. *)

val freeable: Cvalue.V.t -> Abstract_interp.truth
(** Evaluates the ACSL predicate \freeable(value): holds if and only if the
    value points to an allocated memory block that can be safely released using
    the C function free. Note that \freeable(\null) does not hold, despite NULL
    being a valid argument to the C function free. *)

(** {2 Tables of the policy [by_stack], and replay of its decisions} *)

(** Folds over the lists of the blocks that the policy [by_stack] made, by
    stack, the first block made first. A stack is the callstack of a call of
    an allocation builtin, whose innermost call is removed while the two
    innermost calls are both calls of functions of option
    [-eva-alloc-functions]. For the tests. *)
val fold_malloced_by_stack: (Callstack.t -> Base.t list -> 'a -> 'a) -> 'a -> 'a

(** [malloced_on stack] is the list of the blocks that the policy [by_stack]
    made on the stack [stack], the first one made first, as
    [fold_malloced_by_stack] gives it; the empty list if it made none. *)
val malloced_on: Callstack.t -> Base.t list

(** With option [-eva-hit-log], memexec stores and reuses a call that
    allocates with [malloc] (#127), [calloc], [realloc] or [reallocarray]
    (#129) under the policy [by_stack]. A reuse replays each decision of the
    policy that the analysis of the stored call took, in the order it took
    them, on the callstack [stack] of the allocation in the call that reuses
    it, without running the policy again and without emitting a heap
    effect. Neither function writes the content of the block, which the
    reuse takes from the states of the stored call. Both return the block:
    - [replay_creation ~stack ~rank ~builtin size] creates the block of rank
      [rank] on [stack] for a request of [size] bytes, as [builtin] does when
      the list of the blocks of [stack] has [rank] blocks, with the name that
      [builtin] gives it, and adds it to the tables of the allocated blocks.
      Fails if the list has another length.
    - [replay_reuse ~stack ~rank ~weakened size] reuses the block of rank
      [rank] on [stack], weakened if [weakened], and resizes it to [size]
      bytes, as the builtin does, which changes its type as well. Fails if
      the list has no block of this rank. *)
val replay_creation:
  stack:Callstack.t -> rank:int -> builtin:Heap_effects.builtin ->
  Cvalue.V.t -> Base.t
val replay_reuse:
  stack:Callstack.t -> rank:int -> weakened:bool -> Cvalue.V.t -> Base.t
