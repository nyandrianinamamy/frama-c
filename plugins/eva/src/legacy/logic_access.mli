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
    The collector is inactive here when there is no active body recorder.
    During {!Body_access.at_call_site}, the clause is a requires clause of
    the body: its observations go to the allocation family of the body
    ({!Body_access.at_call_site}). *)
val with_clause : kind -> (unit -> 'a) -> 'a
val is_recording : unit -> bool

(** Refuses a clause that accesses an unsupported side table. *)
val refuse_side_table : unit -> unit

(** Sets the read bound to Top and records its clause's refusal reason. *)
val unknown_read : unit -> unit

(** Reports a location before validity narrowing. An unknown location sets
    the read bound to Top, or refuses as [footprint-top] at a call site. *)
val read : Locations.t -> unit

(** Reports pointer targets. Unknown targets refuse as [footprint-top] and
    leave the read bound unchanged: a load reports its location itself. *)
val designate : Cvalue.V.t -> unit
val designate_bits : Addresses.Bits.t -> unit
val designate_raw : Cvalue.V_Or_Uninitialized.t -> unit

(** Reports a load from a state: the location, as [read], and the targets of
    the values in each cell that the load may combine. *)
val load : Cvalue.Model.t -> Locations.t -> unit

(** Reports changed cvalue bindings as possible writes of a reduction.
    An infeasible successor has no bindings to propagate. *)
val record_reduction : before:Cvalue.Model.t -> after:Cvalue.Model.t -> unit
