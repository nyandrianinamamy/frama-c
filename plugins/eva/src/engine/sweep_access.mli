(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** [clear_input targets input] requires that the input omits the
    swept locals and that its map has no offsetmap cell that may point to
    a swept local. This is stronger than
    the frame condition, since it checks the blocks of the key and overlay
    as well. A missing binding has a pointer-free default. *)
val clear_input : Base.Hptset.t -> Cvalue.Model.t -> bool
