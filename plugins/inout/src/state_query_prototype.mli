(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Temporary instrumentation for the controlled state-query experiment. *)

type prefix = {
  reads : Memory_zone.t;
  may_write : Memory_zone.t;
  sure_write : Memory_zone.t;
}

val selected : Cil_types.kernel_function -> bool

(** [body kf results id state prefix edges local_edges] records the analysis
    of a body, under the producer [id] of the collection hooks. It takes the
    input of the invocation, before the preconditions, from [results];
    [state] is the state passed to the hook with [results]: the join of the
    entries that survive the preconditions, or top if none does. *)
val body :
  Cil_types.kernel_function ->
  Eva.Cvalue_callbacks.results ->
  int ->
  Cvalue.Model.t ->
  (Cil_types.stmt -> prefix) ->
  (Cil_types.stmt -> (Cil_types.stmt * prefix) list) ->
  (Cil_types.stmt -> (Cil_types.stmt * prefix) list) ->
  unit

(** Records an invocation and its input: from the results of an analyzed
    body, or the state passed to the hook for a memexec hit. *)
val record : Eva.Cvalue_callbacks.call_results_hook
