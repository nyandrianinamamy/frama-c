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

(** Minimal signature required to instantiate a cell memory model. *)
module type Lattice = sig
  include Datatype.S
  val top : t
  val is_included : t -> t -> bool
  val join : t -> t -> t
  val narrow : t -> t -> t or_bottom
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
end

(** Minimal signature required on abstract values. *)
module type Value =
sig
  include Abstract_value.Leaf
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
  val builtins: (string * t builtin) list
end

(** This functor builds the cell memory model. *)
module Make_Memory (Value : Lattice) :
sig
  include Datatype.S_with_collections
  type oracle = Cell_oracle.oracle
  type location = Cell_location.t

  val top : t
  val is_included : t -> t -> bool
  val join : t -> t -> t
  val narrow : t -> t -> t or_bottom
  val widen : Cil_types.kernel_function -> Cil_types.stmt -> t -> t -> t

  (* For all the following functions, if no oracle is provided, the functions
     use the default oracle provided by [Cell_oracle]. *)

  (* Reads and return all information recorded for a given set of locations.
     The function returns a triplet composed of the recorded cvalue, the
     recorded value and a boolean set to true if the locations are initialized.
     The call returns bottom if no information has been recorded for the set. *)
  val get : ?oracle:oracle -> t -> location ->
    (Cvalue.V.t * Value.t * bool) or_bottom

  (* Same as the previous function, but only returns the value. Abort if no
     value has been recorded for the set of locations. *)
  val read : ?oracle:oracle -> t -> location -> Value.t

  (* Set a value on a set of locations *)
  val set : ?oracle:oracle -> t -> location -> Cvalue.V.t -> Value.t -> t

  (* Remove all information on a given varinfo. *)
  val remove : ?oracle:oracle -> Cil_types.varinfo -> t -> t

  (* The call [replace state dst src] replaces all information for the [dst]
     location by the ones recorded for the [src] location. *)
  val replace : ?oracle:oracle -> t -> location -> location -> t

  (* Erase / initialize the memory on a set of locations. *)
  val erase : ?oracle:oracle -> ?weak:bool -> t -> location ->
    Abstract_memory.bit -> t

  (* Reinforce values on a set of locations when the locations match the
     memory structure ; does nothing on locations that cannot be matched *)
  val reinforce : ?oracle:oracle ->
    (Cvalue.V.t * Value.t -> (Cvalue.V.t * Value.t) or_bottom) ->
    t -> location -> t or_bottom

  (* Iterators over memories. *)
  val map  : (location -> Value.t -> Value.t) -> t -> t
  val iter : (location -> Value.t -> unit) -> t -> unit
  val fold : (location -> Value.t -> 'a -> 'a) -> t -> 'a -> 'a

  val set_tracking : t -> Base.t list -> t
  val add_references : t -> Base.t -> Base.t list -> t
  val remove_references : ?oracle:oracle -> Base.t -> t -> t
  val update_references : ?oracle:oracle -> location -> Eva_ast.exp option -> t -> t

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
