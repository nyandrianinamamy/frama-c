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

(** With [snapshot ()], a call is also matched with the snapshot of the
    allocated blocks it mentions: the blocks of its key, and those that a
    pointer value of its arguments or of its key at its start may point to.
    The snapshot of a block is its strength, its validity record, its type
    and its kind, copied when the call is stored. A stored call is reused
    only if each block of its snapshot has the same strength, record, type
    and kind at the call. A call whose arguments or key hold a pointer to an
    unknown set of blocks is not stored. Blocks are compared by identity.
    The statistic [hit-log-snapshot-misses] counts, per function, the calls
    that are not reused although a stored call has their input state, because
    the snapshot of a block differs. *)
module Make
    (Value : Engine_abstractions_sig.Value)
    (Domain : Engine_abstractions_sig.Domain)
    (_ : sig val snapshot : unit -> bool end)
  : sig

    (** [store_computed_call kf init_state args call_results] memoizes the fact
        that calling [kf] with initial state [init_state] and arguments [args]
        resulted in the results [call_results]. Those information are intended
        to be reused in subsequent calls *)
    val store_computed_call:
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      (Partition.key * Domain.t) list ->
      unit

    (** [reuse_previous_call kf init_state args] searches amongst the previous
        analyzes of [kf] one that matches the initial state [init_state] and the
        values of arguments [args]. If none is found, [None] is returned.
        Otherwise, the results of the analysis are returned, together with the
        index of the matching call. (This last information is intended to be used
        by the plugins that have registered Value callbacks.) *)
    val reuse_previous_call:
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      ((Partition.key * Domain.t) list * int) option

    (** [has_previous_call kf init_state args] is whether
        [reuse_previous_call kf init_state args] would find a previous
        analysis. Unlike [reuse_previous_call], it counts neither a hit nor a
        miss in the statistics. *)
    val has_previous_call:
      kernel_function -> Domain.t -> Value.t or_bottom list -> bool
  end
