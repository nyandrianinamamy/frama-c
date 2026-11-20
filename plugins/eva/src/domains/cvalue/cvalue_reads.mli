(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Reads of the cvalue results by the readers that the engine depends on
    (prototype): the logic label Init and the printing of the final states.
    They read what the public requests read: the records of {!Hit_log} when
    they describe the current results, the legacy store otherwise. The
    engine installs these reads, since the hit log and the public getter
    depend on these readers; until then, they read the legacy store. *)

open Lattice_bounds

(** The initialized globals, before the binding of the formals of the entry
    point, for the label Init. Available while the analysis runs, once the
    initial state is computed. *)
val initial_state: unit -> Cvalue.Model.t or_top_bottom

(** The state before a statement, joined over its callstacks, as the
    unfiltered public request answers it. *)
val before: Cil_types.stmt -> Cvalue.Model.t or_top_bottom

(** Installs the reads. Called by the engine. *)
val install:
  initial_state:(unit -> Cvalue.Model.t or_top_bottom) ->
  before:(Cil_types.stmt -> Cvalue.Model.t or_top_bottom) -> unit
