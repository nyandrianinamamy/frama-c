(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval


(** {2 Cell Memory Model functors} *)

type 'value builtin = 'value list -> 'value Lattice_bounds.or_bottom

(** Minimal signature required on abstract values. *)
module type Value =
sig
  include Abstract_value.Leaf
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
  val builtins: (string * t builtin) list
end

(** This functor builds the cell memory model. *)
module Make_Memory (Value : Value) :
sig
  include Datatype.S_with_collections

  val top : t
  val is_included : t -> t -> bool
  val join : t -> t -> t
  val narrow : t -> t -> t or_bottom
  val widen : Cil_types.kernel_function -> Cil_types.stmt -> t -> t -> t

  val read : t -> Eva_ast.lval -> Value.t
  val get : t -> Cell_location.t -> Value.t or_bottom
  val set : t -> Cell_location.t -> Cvalue.V.t -> Value.t -> t
  val remove : Cil_types.varinfo -> t -> t
  val replace : t -> Cell_location.t -> Cell_location.t -> t
  val erase : ?weak:bool -> t -> Cell_location.t -> Abstract_memory.bit -> t
  val reinforce : (Value.t -> Value.t or_bottom) -> t -> Cell_location.t -> t or_bottom

  val map  : (Cell_location.t -> Value.t -> Value.t) -> t -> t
  val iter : (Cell_location.t -> Value.t -> unit) -> t -> unit
  val fold : (Cell_location.t -> Value.t -> 'a -> 'a) -> t -> 'a -> 'a
  val filter : (Cell_location.t -> Value.t -> bool) -> t -> t

  val set_tracking : t -> Base.t list -> t
  val add_references : t -> Base.t -> Base.t list -> t
  val remove_references : Base.t -> t -> t
  val update_references : Cell_location.t -> Eva_ast.exp option -> t -> t

  val project : Base.Hptset.t -> t -> t
  val overwrite : Base.Hptset.t -> on:t -> by:t -> t
end

(** This functor builds an abstract domain with the cell memory model. *)
module Make (_ : sig val name : string end) (Value : Value) :
  Abstract_domain.Leaf
  with type value = Cvalue.V.t * Value.t
   and type location = Precise_locs.precise_location


(** {2 The "multidim" domain} *)

module MultidimDomain :
  Abstract_domain.Leaf
  with type value = Cvalue.V.t
   and type location = Precise_locs.precise_location

val registered: Abstractions.Domain.registered
