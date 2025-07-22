(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Memory locations *)
type t =
  | Var of Eva_ast.varinfo (** A simple variable, possibly global *)
  | HeapBlk of Cil_types.stmt (** A block on the heap *)
  | InputMem (** A location coming from pointer arguments *)

include Datatype.S with type t := t

module Set : Hptset.S with type elt = t
module Map (V : Datatype.S) : Hptmap_sig.S with type key = t and type v = V.t
module SetMap : Hptmap_sig.S with type key = t and type v = Set.t

module Util (_ : sig val ptr_targets : SetMap.t end) :
sig
  open Eva_ast_types

  val locs_of_lval : lval -> Set.t
  (** The locations of an lvalue *)

  val locs_of_exp : exp -> Set.t
  (** The locations involved in an expression *)

  val locs_of_nested_lval : lval -> Set.t
  (** The locations involved when an lvalue is nested in an expression *)

  val locs_of_deref : t -> Set.t
  (** The locations reached when dereferencing *)

  val locs_of_init : init -> Set.t
  (** The locations involved in an initializer *)

  val recursive_locs : Set.t -> Set.t
  (** [recursive_locs locs] gives [locs] united with all the locations that can
      be reached by dereferencing [locs] any number of times. *)

  val typ_is_ptr : typ -> bool
  (** If a type is a pointer type *)
end
