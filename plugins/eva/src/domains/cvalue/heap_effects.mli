(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Heap effects: the effects of the analysis on the allocated blocks, other
    than the reads and writes of their contents. With option [-eva-hit-log],
    they are emitted where they happen, to the sinks registered here: the
    hit log records them for the call being analysed. Without the option,
    nothing is emitted.

    There are four effects:
    - an allocation, by the builtins of [malloc], [calloc], [realloc],
      [reallocarray], [alloca] and of the allocation of a variable-length
      array: it creates a block or reuses one, and, for [realloc], reads the
      blocks whose content it copies there;
    - a validity mutation, by the same builtins when they reuse a block, and
      by the widening of a memory map, which raises the validity of a weak
      block in place (see {!Lmap.register_validity_widening_hook});
    - a removal, by a [free] that releases one block, by the release of a
      variable-length array, and by the automatic release of the blocks of
      [alloca] and of variable-length arrays at the end of a call;
    - a sweep, by the same releases and by a [free] on several blocks or on
      a weak block: the pointers to the released blocks become escaping
      addresses, everywhere in the state. *)

(** The decision of an allocation: a new block, or a block that the policy
    reuses. [weakened] is what the policy asks for the reused block, to be
    weak from now on, whether or not it was weak already; the change of
    strength itself, if any, is in the validity mutation that follows. *)
type decision =
  | Created
  | Reused of { weakened: bool }

(** The builtin that makes an allocation, which gives the name of the block
    it creates and what it writes in the block. *)
type builtin =
  | Malloc
  (** [malloc], [alloca] and the allocation of a variable-length array: the
      block is uninitialized. *)
  | Calloc (** [calloc]: the block is filled with zeroes. *)
  | Realloc
  (** [realloc] and [reallocarray]: the block receives a copy of the
      content of the blocks that the allocation copies, which the builtin
      releases after it. *)

(** The validity record of an allocated block, in bits. *)
type record = { min_alloc: Z.t; max_alloc: Z.t }

type t =
  | Allocation of {
      block: Base.t; (** The block created or reused. *)
      builtin: builtin;
      copied: Base.Hptset.t;
      (** The blocks whose content the builtin copies into the block, read
          by the allocation: the blocks that [realloc] releases, except under
          the policy [imprecise], where it copies nothing. Empty for the
          other builtins. *)
      policy: Eva_annotations.allocation_kind; (** The policy that applied. *)
      stack: Callstack.t;
      (** The callstack of the allocation, without the calls of the
          functions of option [-eva-alloc-functions] that its bottom ends
          with, as the policy [by_stack] uses it. *)
      rank: int option;
      (** Under the policy [by_stack], the rank of the block among the blocks
          allocated on [stack]; [None] under the other policies. *)
      size: Cvalue.V.t; (** The size requested, in bytes. *)
      typ: Cil_types.typ;
      (** The type of the elements of the block, as guessed from the
          statement of the allocation. *)
      decision: decision;
    }
  | Mutation of {
      block: Base.t;
      record: (record * record) option;
      (** The validity record before and after, if it changed. *)
      weakened: bool; (** Whether the block became weak. *)
      typ: (Cil_types.typ * Cil_types.typ) option;
      (** The type of the block before and after, if it changed. *)
    }
  | Removal of Base.t
  (** The block leaves the state. Not emitted for a block that the state
      does not hold. *)
  | Sweep of { block: Base.t; exact: bool }
  (** The pointers to [block] become escaping addresses: in place of the
      pointer if [exact], joined with it otherwise. *)

val pretty: Format.formatter -> t -> unit

(** Whether the effects are emitted: option [-eva-hit-log] is set. An
    emitter tests it before it builds an effect. *)
val enabled: unit -> bool

(** [register_sink f] makes each emission of an effect [e] call [f ?point e],
    after the sinks registered before. [point] is the statement where the
    effect happens, in the function of the call being analysed, when the
    emitter knows it: the statement of the call that ends, for the automatic
    release, and the statement of the loop, for the widening. A builtin
    gives no statement: it runs in a call of its own. *)
val register_sink: (?point:Cil_types.stmt -> t -> unit) -> unit

(** Emits an effect to the sinks. *)
val emit: ?point:Cil_types.stmt -> t -> unit

(** [register_whole_heap_reader f] makes each call of {!read_whole_heap}
    call [f ()], after the functions registered before. *)
val register_whole_heap_reader: (unit -> unit) -> unit

(** Signals that the builtin being run reads every allocated block of the
    state, as the builtin of [Frama_C_check_leak] does. Nothing is signalled
    without option [-eva-hit-log]. *)
val read_whole_heap: unit -> unit

(** [at_widening stmt f] runs [f], the widening of the states at [stmt]: the
    validity mutations that the widening of the memory maps makes meanwhile
    are emitted with [stmt] as their point. *)
val at_widening: Cil_types.stmt -> (unit -> 'a) -> 'a
