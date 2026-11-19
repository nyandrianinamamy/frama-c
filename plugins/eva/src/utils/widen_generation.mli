(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** A generation of the dynamic widening hint table within an analysis. *)
type t

val start_run : unit -> unit
val advance : unit -> unit
val current : unit -> t

(** The numeric generation, starting at zero in each analysis. *)
val number : t -> int

(** Compares both the run and the generation in that run. *)
val equal : t -> t -> bool
