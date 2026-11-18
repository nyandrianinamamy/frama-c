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
    module chooses the mechanism behind these two operations:
    - no cache when option [-eva-memexec] is not set;
    - otherwise, the reuse operation on the entries supplied by a test module
      ({!Supplied_entries}) when the current project had such entries when
      the analysis started; this cache stores no result;
    - otherwise, memexec ({!Mem_exec}).

    No analysis has both caches: memexec answers the calls of an analysis
    only when no entry was supplied before it started, and only test modules
    supply entries.
    The rest of the engine uses this module only.

    {2 Dispositions}

    Each call analysed through the body of the called function has three
    dispositions:
    - lookup: [no-candidate] (no entry matches the call), [hit (entry N)],
      or, with supplied entries, the candidates rejected, oldest first, each
      as [rejected (entry N: REASON)], followed by [hit (entry N)] when a
      younger candidate is used;
    - execution: [analysed] (the body is analysed), [not-analysed], or
      [interrupted] (an exception stopped the analysis of the body, for
      instance when the analysis is aborted);
    - storage: [stored (entry N)], [refused (REASON)], or [none] when the
      analysis of the body did not complete.

    They are printed in one message per call under the message category
    [cache], which is off by default:
    {v [eva:cache] FILE:LINE: call to F: lookup: L; execution: E; storage: S v}
    The location is the call site; the message for the entry point of the
    analysis has none. When the message does not fit on the line of its
    header, the log prints it on the next line. The message of a hit is
    printed by the lookup. The message of an analysed call is printed after
    the storage, and the message of an interrupted call when the exception
    leaves it, so both follow the messages of the calls made by the body.

    [N] identifies an entry within one run. With memexec, a hit names the
    entry stored by an earlier call whose message reads [stored (entry N)],
    and [N] is the number given to the analysis of the body that produced the
    entry, which is also the number sent to the callbacks registered through
    {!Cvalue_callbacks} with [`Body] and [`Reuse]. With supplied entries, [N]
    is the identifier of a supplied entry ({!Supplied_entries.id}), also sent
    with [`Reuse].

    REASON is the stable identifier of a {!refusal}, given by {!refusal_id},
    for a storage, and of a {!Supplied_entries.rejection}, given by
    {!Supplied_entries.rejection_id}, for a rejected candidate.

    With [-eva-cache-collect], a completed body also reports [collector:
    would-store] or [collector: refused (REASON)] on the same line. This
    verdict describes the observed body and does not control memexec. With
    supplied entries, a body analysed after a lookup that found no candidate
    or rejected every candidate reports its verdict beside [refused
    (supplied-only)]; the verdict stores nothing. A hit analyses no body, and
    its message has no verdict.

    {2 Statistics}

    Per function, the statistics count the hits ([memexec-hits]), the lookups
    with no candidate ([memexec-misses]), the stored entries
    ([memexec-stored]) and the refused storages by reason
    ([memexec-refused-REASON]). They count what a cache did: with
    [-eva-no-memexec] no cache is consulted and nothing is counted, although
    each message reads [refused (disabled)]. With supplied entries, memexec
    counts nothing; the statistics count the hits ([cache-hits]), the
    rejected candidates by reason ([cache-rejected-REASON]) and the refused
    storages ([cache-refused-supplied-only]).

    The collector counts [collector-would-store] and [collector-refused-REASON]
    even with [-eva-no-memexec]. It counts completed body computations only. *)

(** Why the result of a call is not stored. *)
type refusal = [
  | `Disabled
  (** Caching is disabled by option [-eva-no-memexec]. *)
  | `Not_cacheable
  (** The result of the call is marked as not cacheable (see
      {!Eval.cacheable}), for instance because the body created a new
      allocated block. *)
  | `No_inout
  (** No Inout result is available for the call. *)
  | `Footprint_top
  (** The inputs or the outputs of the call computed by Inout are not a
      finite set of bases. *)
  | `Relate_top
  (** A domain relates the bases of the key to an unknown set of bases. *)
  | `Relate_unclosed
  (** The closure of the bases of the key under the relations of the domains
      is not reached within the bound of the cache. *)
  | `Exception
  (** An exception was raised while building the entry. *)
  | `Supplied_only
  (** The cache of the analysis holds entries supplied by a test module, and
      stores no result. *)
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
    - [exception] for [`Exception];
    - [supplied-only] for [`Supplied_only]. *)
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

    (** What a lookup with no candidate leaves for the storage of the result
        of the same call, or for the message of its interruption. *)
    type pending

    (** Result of a lookup. *)
    type lookup =
      | No_candidate of pending
      (** No entry matches the call, or every candidate is rejected: its body
          must be analysed. *)
      | Hit of int * (Partition.key * Domain.t) list
      (** An entry matches the call: its identifier, and the states at the
          end of the call computed from the entry. *)

    (** [lookup call state] looks up the cache for an entry that matches the
        call [call] in the state [state], before the body of the called
        function is analysed. On a hit, it prints the message of the call and
        counts the hit; otherwise, if a cache was consulted, it counts a
        lookup with no candidate. *)
    val lookup : ('loc, Value.t) Eval.call -> Domain.t -> lookup

    (** [store ~save_results call state pending result footprint] offers the
        [result] of analysing the body of the called function, after a
        lookup that found no candidate for the call [call] in the state
        [state] and returned [pending]. It prints the message of the call
        and, if a cache was consulted, counts the stored entry or the refused
        storage. If [footprint] is present, it also reports and counts the
        collector verdict and the storage of an entry produced from it.
        [save_results] says whether an Inner reference is available. *)
    val store :
      save_results:bool -> ('loc, Value.t) Eval.call -> Domain.t -> pending ->
      Domain.t Engine_sig.call_result -> Body_access.Result.t option -> unit

    (** [interrupted call pending] prints the message of the call [call]
        when an exception stops the analysis of the body of the called
        function, after a lookup that found no candidate and returned
        [pending]. Nothing is stored or counted. It never raises: an
        exception raised while the message is printed is dropped, so that
        the caller can raise the first exception again. *)
    val interrupted : ('loc, Value.t) Eval.call -> pending -> unit
  end
