(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Delivery of the Reach part of a cache entry at a hit. *)

(** [deliver callstack ~save_results part] performs again the writes of
    [part] for a call with [callstack]. Each write is made for the
    callstack obtained by putting its frames on top of [callstack]:
    - a reached control point is recorded for that callstack (see
      {!reached}), when [save_results] holds: an analysis of the body saves
      no state otherwise;
    - a guard outcome through {!Iterator.add_condition};
    - read and written zones through {!Inout_access.register}, at the
      position of their statement in that callstack;
    - a call site through {!Function_calls.register_caller}.

    Each write is also recorded in the Reach part of the body being
    analysed, if any. The tables written have no listener and no hook. *)
val deliver : Callstack.t -> save_results:bool -> Reach_part.t -> unit

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

    A hit on an entry without a Reach part, such as an entry supplied by a
    test without one, delivers no reached statement: the passes run at the
    end of the analysis must not conclude from the absence of a state at a
    statement of the called function. *)

(** [reach_unknown kf] records that a hit on an entry without a Reach part
    has answered a call of [kf] in the current analysis. The record is a
    state of the analysis, and is reset with it. *)
val reach_unknown : Cil_types.kernel_function -> unit

(** Whether a hit on an entry without a Reach part has answered a call of
    the function in the current analysis. *)
val reach_unknown_of : Cil_types.kernel_function -> bool

(** Whether a hit on an entry without a Reach part has answered a call of
    the function that contains the statement, in the current analysis. *)
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
