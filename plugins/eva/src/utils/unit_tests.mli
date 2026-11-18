(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Currently tested by this module:
    - semantics of sign values;
    - consequences of the laws of the reuse operation on the cvalue domain
      that need no concretization: [filter] is idempotent and only forgets,
      and [reuse W S (filter (K ∪ W) S) = S]. *)

(** Runs some programmatic tests on Eva. *)
val run: unit -> unit
