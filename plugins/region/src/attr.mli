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

type mask

val generate_mask : attr list -> mask (** Generate the mask under which only the flags specified as input will be counted as effective *)

val empty : flags
val add : attr -> flags -> flags
val mem : attr -> flags -> bool
val subset : flags -> flags -> bool
val union : flags -> flags -> flags (** Union of attributes under the mask [mask] when specified *)

val bottom : flags
(** Neutral for merge *)

val add_flag : flags -> attr -> flags
val merge : ?mask:mask -> flags -> flags -> flags
(** [merge ?mask x y]: combine flags under [mask] when specified:
    - [`Nullable] if {i either} is nullable
    - [`Allocated] if {i either} is allocated
    - [`Garbage] if {i either} is garbage
    - [`Validread] if {i both} are validread (meaningful only for [objects])
    - [`Written] if {i either} is written (meaningful only for [regions])
      It merges all flags appearing in [mask] from both [x] and [y].
      It keeps from [x] all flags not appearing in [mask].
*)

val iter : (attr -> unit) -> flags -> unit

val pp_attr : Format.formatter -> attr -> unit
val pretty : Format.formatter -> flags -> unit

open Cil_types

val cvar : garbage:bool -> varinfo -> flags
val is_local : varinfo -> bool
val is_const : varinfo -> bool
val is_initialized : garbage:bool -> varinfo -> bool
