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

(** Whether two snapshots are equal. *)
val equal_block: block -> block -> bool

(** A renaming: pairs of blocks, from the blocks of the call that computed a
    cache entry to those of a call that reuses it. The empty list is the
    identity. *)
type renaming = (Base.t * Base.t) list

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
      snapshot:bool ->
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      (Partition.key * Domain.t) list ->
      Base.t list option

    (** [reuse_previous_call kf init_state args] searches amongst the previous
        analyzes of [kf] one that matches the initial state [init_state] and the
        values of arguments [args]. If none is found, [None] is returned.
        Otherwise, the results of the analysis are returned, together with the
        index of the matching call (This information is intended to be used
        by the plugins that have registered Value callbacks.) and the
        renaming from the blocks of the matching call to those of this
        call: the identity unless the call was stored in numbered form. *)
    val reuse_previous_call:
      snapshot:bool ->
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      ((Partition.key * Domain.t) list * int * renaming) option

    (** [has_previous_call kf init_state args] is whether
        [reuse_previous_call ~snapshot:false kf init_state args] would find a
        previous
        analysis. Unlike [reuse_previous_call], it counts neither a hit nor a
        miss in the statistics. *)
    val has_previous_call:
      kernel_function -> Domain.t -> Value.t or_bottom list -> bool
  end
