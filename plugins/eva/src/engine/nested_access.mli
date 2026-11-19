(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Whole-block operations for the composition of a call with its caller. *)

(** The formals, the automatic locals and the return slot of the callee. *)
val private_blocks :
  Cil_types.kernel_function -> Cil_types.varinfo option -> Base.Hptset.t

(** Set difference, preserving [Top]. *)
val remove : Base.Hptset.t -> Base.SetLattice.t -> Base.SetLattice.t

(** The ranges of blocks with a known fixed validity. *)
val sure_zone : Base.Hptset.t -> Memory_zone.t

(** Blocks whose whole known range is included in the given sure-write zone. *)
val fully_written : Memory_zone.t -> Base.Hptset.t
