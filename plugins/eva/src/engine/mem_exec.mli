(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types
open Eval

(** Counter that must be used each time a new call is analyzed, in order
    to refer to it later *)
val new_counter : unit -> int

(** Clean all previously stored results *)
val cleanup_results: unit -> unit

(** [register_store_hook f] makes memexec call [f kf id entry] each time it
    stores, with [~snapshot:true] (option -eva-hit-log), a call of [kf] as
    the cache entry of number [id]: [entry] is the cvalue part of the call
    it stores, before any numbering, the arguments, the key, the start state
    on the key and the states at the exits, each with its clobbered set.
    Nothing is computed for the hooks when none is registered, or without
    the cvalue domain. For the tests of the numbered form. *)
val register_store_hook:
  (Cil_types.kernel_function -> int -> Numbering.entry -> unit) -> unit

(** The snapshot of an allocated block: its strength, validity record, type
    and kind, as a cache entry records them. *)
type block

(** The snapshot of a block as it is now; [None] if it is not allocated. *)
val take_block: Base.t -> block option

(** [take_block_at_entry ~mutations base] is the snapshot of [base] at the
    start of a call that has made since then the validity mutations
    [mutations], see {!Heap_effects}, in the order of emission: each field
    that a mutation changed is taken back to its value before the first
    mutation that changed it. A removal changes no field of the snapshot.
    [None] if [base] is not allocated. *)
val take_block_at_entry:
  mutations:Heap_effects.t list -> Base.t -> block option

(** Whether two snapshots are equal. *)
val equal_block: block -> block -> bool

(** A renaming: pairs of blocks, from the blocks of the call that computed a
    cache entry to those of a call that reuses it. The empty list is the
    identity. *)
type renaming = (Base.t * Base.t) list

(** An allocation of a heap call that memexec stores (#127): [block], the
    block it creates or reuses; [suffix], the calls from the heap call down
    to the call of [malloc], innermost first, of the callstack of the
    allocation without the allocation wrappers, as the policy [by_stack]
    reads it; [rank], the rank of the block among the blocks made on this
    stack; [size], the size requested; [decision], the decision of the
    policy. *)
type allocation = {
  block: Base.t;
  suffix: Callstack.call list;
  rank: int;
  size: Cvalue.V.t;
  decision: Heap_effects.decision;
}

(** What memexec stores of a heap call (see {!Hit_log}): a call that frees,
    whose heap effects are removals and sweeps only, or a call that also
    allocates with [malloc] under the policy [by_stack] (#127).
    [removed], the blocks it removes; [swept], the blocks it sweeps at any
    point of its body; [exit], the blocks swept on every path from its start
    to its return, and on some path only; [mutations], its validity
    mutations, from which the snapshot of its start is rebuilt, see
    {!take_block_at_entry}; [allocations], its allocations, in the order of
    their emission; [candidates], for the stack of each allocation, by the
    order of the first allocation on each, the blocks that the policy had
    made on this stack before the call, the first one made first; and
    [created], the blocks that its allocations create, in the order of their
    creation. *)
type heap = {
  removed: Base.Hptset.t;
  swept: Base.Hptset.t;
  exit: Heap_paths.sweeps;
  mutations: Heap_effects.t list;
  allocations: allocation list;
  candidates: (Callstack.call list * Base.t list) list;
  created: Base.t list;
}

(** [extend callstack suffix] is [callstack] extended by the calls
    [suffix], innermost first. *)
val extend: Callstack.t -> Callstack.call list -> Callstack.t

(** [suffix_below ~callstack stack] is the list of the calls of [stack]
    below [callstack], innermost first, if [stack] extends [callstack] by at
    least one call; [None] otherwise. *)
val suffix_below:
  callstack:Callstack.t -> Callstack.t -> Callstack.call list option

(** With [~snapshot:true] (option -eva-hit-log), a call that mentions an
    allocated block is stored and looked up in numbered form (#120, section
    "Lookup"), see {!Numbering}: its arguments, its key, its start state on
    its key and its states at the exits, with the placeholder of its number
    in place of each allocated block. The mentioned blocks are the blocks of
    its key, and those that a pointer value of its arguments or of its key
    at its start may point to. The entry is stored with its snapshot: the
    strength, validity record, type and kind of each numbered block, copied
    when the call is stored. A lookup numbers the arguments of the call,
    then, for each key stored for these numbered arguments, continues the
    numbering on the state of the call, guided by the key, and looks up the
    state projected on the image of the key, rewritten with numbers. A
    stored call is reused only if each numbered block of the lookup has the
    snapshot that the stored call recorded for its number; if several are,
    the most recent one. Its states at the exits, with their clobbered sets,
    are rewritten back through the numbering of the lookup. The allocated
    blocks of the key that no value leads to are taken by their identity. A
    call whose arguments or key hold a pointer to an unknown set of blocks,
    or whose exits hold a block that the numbering does not reach, is not
    stored. Any other call is stored and looked up as without -eva-hit-log;
    these are looked up first.
    The key of a call is made of its inputs and outputs, as the inout plugin
    gives them, which include those of the calls it makes. The hooks of the
    results of a call that reuses a stored call receive its renaming, as a
    substitution, and the inout plugin replaces the blocks of the inputs and
    outputs of the stored call through it, so that the key of a call names
    the blocks that the calls it makes read and write.
    With [~snapshot:true], a call that frees, given with its removals and
    sweeps [heap], is stored in numbered form only. Its key holds the blocks
    it removes, and every block it sweeps must be numbered, else it is not
    stored. The snapshot of each numbered block is that of the start of the
    call: the snapshot of a block that the call removes is the one it had
    before the removal, which changes no field of it. On a reuse, for each
    exit of the stored call, the pointers of the state of the call to the
    blocks swept on every path are replaced by escaping addresses, and those
    to the blocks swept on some path only are joined with them, through the
    renaming; a block swept on some path only that the exit does not bind is
    swept on every path for this exit. The exit is then copied, and the
    blocks that the stored call removed and that the exit does not bind are
    removed. The statistic [hit-log-stored-heap-calls] counts, per function,
    the heap calls stored by memexec.
    [free] reports the cells that its sweep changes as written: the key of a
    call that frees holds the cells that point to the blocks it frees at its
    start, and the reuse sweeps the cells outside the key that point to them
    at the start of the call that reuses it. On a reuse, the call-results
    hooks receive the results of the stored call: for the inout plugin, its
    inputs and outputs, through the renaming, and the cells outside the key
    that the reuse sweeps, see {!Cvalue_callbacks.swept}, as written, surely
    for a sweep on every path, as a fresh analysis of the call reports them:
    the cells outside the key that point at the start of the call to a
    block that the stored call sweeps at any point are written on some
    path. The inout of the callers of the reuse holds these cells, and so
    do their keys and the dependencies that option -calldeps gives for the
    reuse.
    With [~snapshot:true], a call that allocates, given with its heap
    effects [heap], is stored in numbered form only (#127). Its key holds the
    candidates of its allocations: for each stack on which it allocates, the
    blocks that the policy [by_stack] made on this stack before it, present
    in its start state or not. The blocks it creates are not in its key:
    they are numbered after every other block, in the order of their
    creation, the creation symbols, have no snapshot, and are copied on a
    reuse. Its start state is numbered with the strength of each block at
    its start, its exits with the strength at its end. A lookup reads the
    candidates of the call from the lists of the policy on the stacks of
    the key, extended from the callstack of the call, numbers them after the
    content of the key, and checks the candidate condition: the candidates
    of each stack have the numbers that the stored call recorded, in the
    same order. On a reuse, the allocations of the stored call are replayed
    in their order, after the preconditions of the function are evaluated:
    see [Replayed_hit]. Then its sweeps, its exits and its removals are
    applied as for a call that frees.
    The statistic [hit-log-snapshot-misses] counts, per function, the calls
    that are not reused although a call stored in numbered form has their
    input state, because the snapshot of a block differs. The statistic
    [hit-log-snapshot-results] gives, per function, the largest number of
    results kept at once for one numbered input state.
    With [~snapshot:false], memexec stores and looks up as without
    -eva-hit-log: no call is numbered. *)
module Make
    (Value : Engine_abstractions_sig.Value)
    (Domain : Engine_abstractions_sig.Domain)
  : sig

    (** [store_computed_call kf init_state args call_results] memoizes the fact
        that calling [kf] with initial state [init_state] and arguments [args]
        resulted in the results [call_results]. Those information are intended
        to be reused in subsequent calls. With [~snapshot:true], returns the
        allocated blocks that the stored call mentions, in the order of their
        numbers: the empty list if it mentions none, [None] if the call is not
        stored. Returns [None] with [~snapshot:false]. *)
    val store_computed_call:
      snapshot:bool -> ?heap:heap ->
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      (Partition.key * Domain.t) list ->
      Base.t list option

    (** A previous analysis that a call reuses. *)
    type hit =
      | Hit of (Partition.key * Domain.t) list * int
      (** The results of the analysis, and the index of the matching call
          (This information is intended to be used by the plugins that have
          registered Value callbacks.). *)
      | Renamed_hit of (Partition.key * Domain.t) list * int * renaming
      (** The same, for a call stored in numbered form, with the renaming
          from the blocks of the matching call to those of this call, when
          it is not the identity. *)
      | Replayed_hit of
          (unit ->
           (Partition.key * Domain.t) list * renaming * Cvalue_callbacks.swept)
          * int
      (** The same, for a heap call stored in numbered form: the function
          replays the allocations of a call that allocates (#127) on the
          callstack of the call, which creates blocks, resizes blocks and
          extends the tables of the allocated blocks, sweeps the state and
          copies the exits, then returns the results, the renaming, which
          also maps the blocks that the matching call created to those that
          the replay created, the empty list if it is the identity, and the
          cells swept outside the exits. Nothing is run until it is applied,
          once. *)

    (** [reuse_previous_call kf init_state args] searches amongst the previous
        analyzes of [kf] one that matches the initial state [init_state] and the
        values of arguments [args]. If none is found, [None] is returned.
        Otherwise, the results of the analysis are returned, together with the
        index of the matching call, and with the renaming if it is not the
        identity, which may happen only with [~snapshot:true]. [callstack] is
        the callstack of the call, from which a lookup with [~snapshot:true]
        reads the candidates of the allocations of a stored heap call. *)
    val reuse_previous_call:
      snapshot:bool -> callstack:Callstack.t ->
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      hit option

    (** [has_previous_call kf init_state args] is whether
        [reuse_previous_call ~snapshot:false kf init_state args] would find a
        previous
        analysis. Unlike [reuse_previous_call], it counts neither a hit nor a
        miss in the statistics. *)
    val has_previous_call:
      kernel_function -> Domain.t -> Value.t or_bottom list -> bool
  end
