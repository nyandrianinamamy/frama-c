(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Statistics about the analysis performance. *)

(** Call [start] when starting analyzing a new callstack. *)
val start: Callstack.t -> unit

(** Call [stop] when finishing analyzing a callstack. *)
val stop: Callstack.t -> unit

(** Reset the internal state of the module. *)
val reset: unit -> unit

(** Display a complete summary of performance information. Can be
    called during the analysis. *)
val display: Format.formatter -> unit

(** Whether a hook was registered by [StatByCallstack.add_hook_on_change].
    A hook cannot be removed. *)
val has_hooks_on_change : unit -> bool

(** Interface exported via Eva.ml. *)
include Eva_perf_sig.API
