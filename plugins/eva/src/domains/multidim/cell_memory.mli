(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** {2 Cell Memory Model functor }*)

type 'value builtin = 'value list -> 'value Lattice_bounds.or_bottom

module type Value =
sig
  include Abstract_value.Leaf
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
  val builtins: (string * t builtin) list
end

(** This functor builds an abstract domain with the cell memory model. *)
module Make (_ : sig val name : string end) (Value : Value) :
sig
  include Abstract_domain.Leaf
    with type value = Cvalue.V.t * Value.t
     and type location = Precise_locs.precise_location

  val read :
    oracle:(Eva_ast.exp -> Cvalue.V.t) -> t -> Eva_ast.lval -> Value.t

  val map  : (Cil_types.typ -> Value.t -> Value.t) -> t -> t
  val iter : (Cil_types.typ -> Value.t -> unit) -> t -> unit
  val fold : (Cil_types.typ -> Value.t -> 'a -> 'a) -> t -> 'a -> 'a

  val filter_on_value : (Cil_types.typ -> Value.t -> bool) -> t -> t
end

(** {2 The "multidim" domain}*)

module MultidimDomain :
  Abstract_domain.Leaf
  with type value = Cvalue.V.t
   and type location = Precise_locs.precise_location

val registered: Abstractions.Domain.registered
