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

val empty : flags
val add : attr -> flags -> flags
val mem : attr -> flags -> bool
val subset : flags -> flags -> bool
val union : flags -> flags -> flags (** Union of attributes *)
val inter : flags -> flags -> flags (** Intersection of attributes *)

val bottom : flags
(** Neutral for merge *)

val generate_flags : attr list -> flags
val add_flag : flags -> attr -> flags

type mask
val generate_mask : attr list -> mask (** Generate the mask for merge *)
val merge : ?mask:mask -> flags -> flags -> flags
(** [merge ?mask x y]: combine flags under [mask] when specified,
    or equivalent to [union] [x] ([inter] [mask] [y]).
*)

val iter : (attr -> unit) -> flags -> unit

val pp_attr : Format.formatter -> attr -> unit
val pretty : Format.formatter -> flags -> unit

open Cil_types

val cvar : garbage:bool -> varinfo -> flags
val is_local : varinfo -> bool
val is_const : varinfo -> bool
val is_initialized : garbage:bool -> varinfo -> bool
