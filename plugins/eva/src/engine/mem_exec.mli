(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** The memexec cache of calls. The engine uses it through {!Call_cache}. *)

open Cil_types
open Eval

(** Counter that must be used each time a new call is analyzed, in order
    to refer to it later *)
val new_counter : unit -> int

(** Clean all previously stored results *)
val cleanup_results: unit -> unit

(** Why memexec does not store the result of a call. *)
type refusal = [
  | `Not_cacheable
  (** The result of the call is marked as not cacheable (see
      {!Eval.cacheable}). This is the case when the analysis of the body
      performed a call whose callers cannot be cached, such as a call to an
      allocation builtin that created a new block. *)
  | `No_inout
  (** No Inout result is available for the call, usually because the Inout
      plug-in is not loaded. *)
  | `Footprint_top
  (** The inputs or the outputs of the call computed by Inout are not a
      finite set of bases. *)
  | `Relate_top
  (** A domain relates the bases of the key to an unknown set of bases:
      [relate] returns [Top]. *)
  | `Relate_unclosed
  (** The closure of the bases of the key under [relate] is not reached within
      the bound on the number of iterations. *)
  | `Exception
  (** The exception [Not_found] or [Kernel_function.No_Statement] was raised
      while building the entry. *)
]

module Make
    (Value : Datatype.S)
    (Domain : Engine_abstractions_sig.Domain)
  : sig

    (** [store_computed_call kf init_state args call_result] memoizes the fact
        that calling [kf] with initial state [init_state] and arguments [args]
        resulted in the result [call_result]. Those information are intended
        to be reused in subsequent calls. Returns the number of the call
        stored with the entry, which [reuse_previous_call] returns on a match,
        or the reason why nothing is stored. *)
    val store_computed_call:
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      Domain.t Engine_sig.call_result -> (int, refusal) result

    (** [reuse_previous_call kf init_state args] searches amongst the previous
        analyzes of [kf] one that matches the initial state [init_state] and the
        values of arguments [args]. If none is found, [None] is returned.
        Otherwise, the results of the analysis are returned, together with the
        index of the matching call. (This last information is intended to be used
        by the plugins that have registered Value callbacks.) *)
    val reuse_previous_call:
      kernel_function -> Domain.t -> Value.t or_bottom list ->
      ((Partition.key * Domain.t) list * int) option
  end
