(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Delivery of the Safety part of a cache entry at a hit. *)

(** [deliver callstack part] performs again, in their order, the writes of
    [part] for a call with [callstack]. Each write is made while the current
    callstack is the one obtained by putting its frames on top of
    [callstack]. It is also recorded in the Safety part of the body being
    analysed, if any. Each write goes through the function that the body
    uses to emit it:
    - an alarm through {!Alarmset.deliver}, so that the kernel combines its
      status with the existing one;
    - a status through {!Safety_part.emit_status}, so that the kernel
      combines it with the statuses that the same emitter emitted before on
      the same property;
    - the message of a status through {!Safety_part.status_message}, at
      each of its occurrences, so that the action of its message category
      applies, and the logger decides at each one whether the text was
      printed before at the same position;
    - a red context through {!Red_statuses.add_red_context}, at each of its
      occurrences, which adds the callstack of the write to the contexts of
      its alarm or property, and runs the hooks of red statuses.

    The writes are delivered in the order of the Safety part, which is the
    order of the analysis of the body. A hit is admitted only when no
    client that is not audited is registered on the hooks that it runs
    (see {!Supplied_entries}): the delivery then makes the recorded
    sequence of writes, and nothing else runs between them. *)
val deliver : Callstack.t -> Safety_part.t -> unit

(** {2 Functions with skipped visits}

    A hit delivers the Safety part of its entry, but saves no state for the
    statements of the called function: the visits of these statements by
    the call are skipped. The hit delivers the points it reaches
    ({!Reach_delivery}), where the state of its callstack is [top]; the
    passes run at the end of the analysis read these points, and Export and
    the server request of dead code skip the functions of unknown
    reachability ({!Reach_delivery.reach_unknown_of}). The values at these
    points are not those of the call: the results computed from the values
    that the states saved at statements give, such as the dependencies of
    From and the inputs and outputs of Inout by function, and the results
    of the callers computed from them, are incomplete; their readers refuse
    them while the record below is not empty ({!complete}). The record also
    serves the statistics of a function, computed again after each such
    hit. The functions called by the body of an entry would be skipped as
    well; no hit skips one, since {!Supplied_entries.supply} refuses a body
    that may call a function that has a body, and the lookup rejects an
    entry given to {!Supplied_entries.supply_produced} whose body contains
    another call. Memexec saves the states of the analysis that produced
    its entry, in the same analysis, and is not concerned.

    The record is one state of the analysis, saved with the session, copied
    with the project, kept in the results taken by
    {!Eva_results.get_results} ({!Reach_delivery.records}), and reset with
    the analysis. *)

(** [skip_visits kf] records that a hit has answered a call of [kf] in the
    current analysis. *)
val skip_visits : Cil_types.kernel_function -> unit

(** Whether a hit has answered a call of the function in the current
    analysis. *)
val visits_skipped : Cil_types.kernel_function -> bool


(** Whether no hit has answered a call in the current analysis: the states
    saved at the statements cover every call of the analysis. *)
val complete : unit -> bool
(** {2 Statistics of the summary} *)

(** [delivered kf] is called by the engine after a hit has delivered the
    Safety part and the Reach part of a call of [kf] and restored the parts
    of its entry. It runs the function given to {!on_delivered}, which
    computes again the statistics of [kf] in the summary of the analysis
    from the tables that the delivery has updated. A hit sends no results
    to the call results hooks of {!Cvalue_callbacks}: its number is not one
    of memexec. *)
val delivered : Cil_types.kernel_function -> unit

(** [on_delivered f] makes {!delivered} run [f]. The summary of the analysis
    calls it once, when Eva is loaded: it depends on the engine, which calls
    {!delivered}. It replaces the function given before, and no other
    module calls it. *)
val on_delivered : (Cil_types.kernel_function -> unit) -> unit
