(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type flags
type attr = [
  | `Nullable (** For [Objects]: either NULL or [\valid]. For [Regions]: might be null. *)
  | `Allocated  (** Might be dynamically allocated. *)
  | `Garbage  (** Might be non-initialized. *)
  | `Validread (** Only for [Objects]: might have no write access  *)
  | `Written (** Only for [Regions]: at least one write access has been recorded in this region. *)
]

val all_flags : flags

val empty : flags
val generate_flags : attr list -> flags

val add : flags -> attr -> flags
val mem : attr -> flags -> bool
val subset : flags -> flags -> bool
val union : flags -> flags -> flags (** Union of attributes *)
val inter : flags -> flags -> flags (** Intersection of attributes *)

val merge : ?mask:flags -> flags -> flags -> flags
(** [merge ?mask x y] is [union x (inter mask y)]. *)

val iter : (attr -> unit) -> flags -> unit

val pp_attr : Format.formatter -> attr -> unit
val pretty : Format.formatter -> flags -> unit

open Cil_types

val cvar : garbage:bool -> varinfo -> flags
val is_local : varinfo -> bool
val is_const : varinfo -> bool
val is_initialized : garbage:bool -> varinfo -> bool
