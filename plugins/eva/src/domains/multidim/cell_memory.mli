(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** {2 Cell Memory Model functor }*)

type 'value assigned = (Precise_locs.precise_location,'value) Eval.assigned
type 'value builtin =
  ('value assigned) list ->
  ('value assigned) Lattice_bounds.or_bottom

module type Value =
sig
  include Abstract_value.Leaf
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
  val builtins: (string * t builtin) list
end

(** This functor builds an abstract domain with the cell memory model. *)
module Make (_ : sig val name : string end) (Value : Value) :
  Abstract_domain.Leaf
  with type value = Cvalue.V.t * Value.t
   and type location = Precise_locs.precise_location


(** {2 The "multidim" domain}*)

module MultidimDomain :
  Abstract_domain.Leaf
  with type value = Cvalue.V.t
   and type location = Precise_locs.precise_location

val registered: Abstractions.Domain.registered
