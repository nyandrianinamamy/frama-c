(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Delivery of the Reach part of a cache entry at a hit. *)

(** [deliver callstack ~save_results part] performs again the writes of
    [part] for a call with [callstack]: those of [part.joins] in any case,
    and those of [part.points] when [save_results] holds, as an analysis of
    the body saves states only then. Each write is made for the callstack
    obtained by putting its frames on top of [callstack]:
    - a reached control point is recorded for that callstack (see
      {!reached});
    - a guard outcome through {!Iterator.add_condition};
    - read and written zones through {!Inout_access.register}, at the
      position of their statement in that callstack;
    - a call site through {!Function_calls.register_caller}.

    [part] must have points when [save_results] holds: the lookup rejects
    it otherwise ([`Missing_points]). When [save_results] holds and the
    store of the states of the cvalue domain, the only domain at a hit,
    saves no state ([-eva-no-results-domain cvalue]), the function is also
    recorded as of unknown reachability ({!reach_unknown}): the queries
    then answer no callstack at any point, and do not see the points of the
    hit, which are delivered all the same.

    Each write is also recorded in the Reach part of the body being
    analysed, if any. The tables written are not in the interface of their
    modules, and no client is registered on their hooks of change. *)
val deliver : Callstack.t -> save_results:bool -> Reach_part.part -> unit

(** {2 Points reached by a hit}

    A hit saves no state at the statements of the called function. Its
    delivered points are recorded in a state of the analysis, reset with
    it and saved with the session, apart from the store of states: the
    states saved by the analysed calls are kept. The store of the engine
    gives the state [top] at a recorded point for a recorded callstack, and
    as the state over all callstacks at that point: the states saved there
    do not cover the visits of the hit, whose states are not recorded. *)

(** Whether a hit has reached the control point in the callstack, or in any
    callstack if none is given. *)
val reached : ?callstack:Callstack.t -> Domain_store.control_point -> bool

(** The callstacks of the hits that reached the control point. *)
val callstacks : Domain_store.control_point -> Callstack.t list

(** {2 Functions of unknown reachability}

    The queries do not see the points that a hit delivers when the store of
    the states saves none: the passes run at the end of the analysis must
    not conclude from the absence of a callstack at a statement of the
    called function. *)

(** [reach_unknown kf] records that a hit whose reached points are not
    known to the queries has answered a call of [kf] in the current
    analysis. The record is a state of the analysis, and is reset with
    it. *)
val reach_unknown : Cil_types.kernel_function -> unit

(** Whether the function is of unknown reachability in the current
    analysis ({!reach_unknown}). *)
val reach_unknown_of : Cil_types.kernel_function -> bool

(** Whether the function that contains the statement is of unknown
    reachability in the current analysis ({!reach_unknown}). *)
val reach_unknown_at : Cil_types.stmt -> bool

(** {2 Saved results}

    The records of the hits of the current analysis that are kept apart
    from the store of states: the points reached by hits, the functions of
    unknown reachability, and the functions whose visits a hit skipped
    ({!Safety_delivery.skip_visits}). They are states of the analysis,
    saved with the session and copied with the project. The results taken
    by {!Eva_results.get_results} hold them, and {!Eva_results.set_results}
    installs them again after it clears the results of the analysis. *)

type records

(** The records of the hits of the current analysis. *)
val records : unit -> records

(** [restore records] adds [records] to those of the current analysis. *)
val restore : records -> unit
