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

val body :
  Cil_types.kernel_function ->
  Eva.Cvalue_callbacks.results ->
  int ->
  Cvalue.Model.t ->
  (Cil_types.stmt -> prefix) ->
  (Cil_types.stmt -> (Cil_types.stmt * prefix) list) ->
  (Cil_types.stmt -> (Cil_types.stmt * prefix) list) ->
  unit

val record : Eva.Cvalue_callbacks.call_results_hook
