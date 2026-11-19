(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Observational call traces of legacy memexec entries in the current run.
    This table is separate from memexec's matching and reuse operations. *)

val remember : int -> Body_access.Result.t -> unit
val find : int -> Body_access.call_trace option
val clear : unit -> unit
