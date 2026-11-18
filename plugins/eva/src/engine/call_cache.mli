(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Seam between the analysis of calls and the cache of calls.

    Before the body of a called function is analysed, the engine looks the
    call up in the cache ({!Make.lookup}). When no entry matches, the body is
    analysed and its result is offered to the cache ({!Make.store}). This
    module chooses the mechanism behind these two operations: memexec
    ({!Mem_exec}) when option [-eva-memexec] is set, and no cache otherwise.
    The rest of the engine uses this module only.

    {2 Dispositions}

    Each call analysed through the body of the called function has three
    dispositions:
    - lookup: [no-candidate] (no entry matches the call), or [hit (entry N)];
    - execution: [analysed] (the body is analysed), or [not-analysed];
    - storage: [stored (entry N)], [refused (REASON)], or [none] when the
      body was not analysed.

    They are printed in one message per call under the message category
    [cache], which is off by default:
    {v [eva:cache] FILE:LINE: call to F: lookup: L; execution: E; storage: S v}
    The location is the call site; the message for the entry point of the
    analysis has none. When the message does not fit on the line of its
    header, the log prints it on the next line. The message of a hit is
    printed by the lookup. The message of an analysed call is printed after
    the storage, so it follows the messages of the calls made by the body.

    [N] identifies an entry within one run: a hit names the entry stored by
    an earlier call whose message reads [stored (entry N)]. With memexec, [N] is
    the number given to the analysis of the body that produced the entry,
    which is also the number sent to the callbacks registered through
    {!Cvalue_callbacks} with [`Body] and [`Reuse].

    REASON is the stable identifier of a {!refusal}, given by {!refusal_id}.

    {2 Statistics}

    Per function, the statistics count the hits ([memexec-hits]), the lookups
    with no candidate ([memexec-misses]), the stored entries
    ([memexec-stored]) and the refused storages by reason
    ([memexec-refused-REASON]). *)

(** Why the result of a call is not stored. *)
type refusal = [
  | `Disabled
  (** Caching is disabled by option [-eva-no-memexec]. *)
  | Mem_exec.refusal
]

(** All reasons, in the order of their documentation. *)
val refusals : refusal list

(** Stable identifier of a reason, as printed under the message category and
    used in the names of the statistics:
    - [disabled] for [`Disabled];
    - [not-cacheable] for [`Not_cacheable];
    - [no-inout] for [`No_inout];
    - [footprint-top] for [`Footprint_top];
    - [relate-top] for [`Relate_top];
    - [relate-unclosed] for [`Relate_unclosed];
    - [exception] for [`Exception]. *)
val refusal_id : refusal -> string

(** Number given to each analysis of a function body. It must be called once
    per analysis of a body; the number is sent to the callbacks registered
    through {!Cvalue_callbacks}, and names the entry stored from this
    analysis, if any. *)
val new_counter : unit -> int

(** Clears all stored entries. *)
val cleanup_results : unit -> unit

module Make
    (Value : Datatype.S)
    (Domain : Engine_abstractions_sig.Domain)
  : sig

    (** Result of a lookup. *)
    type lookup =
      | No_candidate
      (** No entry matches the call: its body must be analysed. *)
      | Hit of int * (Partition.key * Domain.t) list
      (** An entry matches the call: its identifier, and the states at the
          end of the call computed from the entry. *)

    (** [lookup call state] looks up the cache for an entry that matches the
        call [call] in the state [state], before the body of the called
        function is analysed. On a hit, it prints the line of the call and
        counts the hit; otherwise, it counts a lookup with no candidate. *)
    val lookup : ('loc, Value.t) Eval.call -> Domain.t -> lookup

    (** [store call state result] offers the result [result] of the analysis
        of the body of the called function to the cache, after a lookup that
        found no candidate for the call [call] in the state [state]. It prints
        the line of the call and counts the stored entry or the refused
        storage. *)
    val store :
      ('loc, Value.t) Eval.call -> Domain.t ->
      Domain.t Engine_sig.call_result -> unit
  end
