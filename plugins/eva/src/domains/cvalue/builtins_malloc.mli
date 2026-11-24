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

(** Folds over the lists of the blocks that the policy [by_stack] made, by
    stack, the first block made first. A stack is the callstack of a call of
    an allocation builtin, whose innermost call is removed while the two
    innermost calls are both calls of functions of option
    [-eva-alloc-functions]. For the tests. *)
val fold_malloced_by_stack: (Callstack.t -> Base.t list -> 'a -> 'a) -> 'a -> 'a
