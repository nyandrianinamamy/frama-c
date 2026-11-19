(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Functions whose statements have no state for some calls.

    A hit of the reuse operation on a supplied entry (see
    {!Supplied_entries}) answers a call without analysing the body of the
    called function: the visits of its statements by this call are skipped,
    and no state is saved at them for this call. Until a hit delivers the
    statements it reaches (issue #48), the results computed from the states
    saved at statements are incomplete: a statement of such a function may
    look unreachable, and the results of its callers computed from the
    results of the function inherit this. Memexec saves the states of the
    analysis that produced its entry, in the same analysis, and is not
    concerned.

    The record is a state of the analysis, saved with the session and reset
    with the analysis. *)

(** [skip_visits kf] records that a hit has answered a call of [kf] in the
    current analysis. *)
val skip_visits : Cil_types.kernel_function -> unit

(** Whether a hit has answered a call of the function in the current
    analysis. *)
val visits_skipped : Cil_types.kernel_function -> bool

(** Whether a hit has answered a call of the function that contains the
    statement, in the current analysis. *)
val visits_skipped_at : Cil_types.stmt -> bool

(** Whether no hit has answered a call in the current analysis: the states
    saved at the statements cover every call of the analysis. *)
val complete : unit -> bool

(** The functions of which a hit has answered a call in the current
    analysis. *)
val get : unit -> Kernel_function.Set.t

(** [set s] records [s] as the functions of which a hit has answered a call
    in the current analysis. For the installation of saved results only
    ({!Eva_results.set_results}). *)
val set : Kernel_function.Set.t -> unit
