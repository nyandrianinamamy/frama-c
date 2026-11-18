(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Observations of memory accesses during ACSL evaluation and reduction. *)

type kind = Annotation | Contract

(** Classifies observations during the evaluation or reduction of a clause.
    The collector is inactive here when there is no active body recorder. *)
val with_clause : kind -> (unit -> 'a) -> 'a
val is_recording : unit -> bool

(** Refuses a clause that accesses an unsupported side table. *)
val refuse_side_table : unit -> unit

(** Sets the read bound to Top and records its clause's refusal reason. *)
val unknown_read : unit -> unit

(** Reports a location before validity narrowing. *)
val read : Locations.t -> unit

(** Reports pointer targets, keeping the clause's reason for unknown targets. *)
val designate : Cvalue.V.t -> unit
val designate_bits : Addresses.Bits.t -> unit
val designate_raw : Cvalue.V_Or_Uninitialized.t -> unit

(** Reports changed cvalue bindings as possible writes of a reduction.
    An infeasible successor has no bindings to propagate. *)
val record_reduction : before:Cvalue.Model.t -> after:Cvalue.Model.t -> unit
