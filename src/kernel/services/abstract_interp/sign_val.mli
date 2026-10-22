(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Sign domain: abstraction of integer numerical values by their signs. *)

type signs = {
  pos: bool;  (** true: maybe positive, false: never positive *)
  zero: bool; (** true: maybe zero, false: never zero *)
  neg: bool;  (** true: maybe negative, false: never negative *)
}

include Datatype.S with type t = signs

val top : signs
val pos_or_zero : signs
val pos : signs
val neg_or_zero : signs
val neg : signs
val zero : signs
val non_zero : signs

val ge_zero : signs -> bool
val le_zero : signs -> bool
val gt_zero : signs -> bool
val lt_zero : signs -> bool

val inject_int : Z.t -> signs

val neg_unop : signs -> signs
val bitwise_not : signs -> signs
val logical_not : signs -> signs

val plus : signs -> signs -> signs
val mul : signs -> signs -> signs

(** Computer division with ACSL like semantics: e / (maybe zero) = top *)
val cdiv : signs -> signs -> signs

(** Computer modulo with ACSL like semantics: e / (maybe zero) = top *)
val cmod : signs -> signs -> signs

val bitwise_and : signs -> signs -> signs
val bitwise_or : signs -> signs -> signs
val bitwise_xor : signs -> signs -> signs

(** ACSL like semantics: a << negative = a >> positive *)
val bitwise_lsl : signs -> signs -> signs

(** ACSL like semantics: a >> negative = a << positive *)
val bitwise_lsr : signs -> signs -> signs

val logical_and : signs -> signs -> signs
val logical_or : signs -> signs -> signs
