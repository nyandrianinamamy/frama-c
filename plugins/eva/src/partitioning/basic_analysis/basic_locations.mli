(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* Memory locations *)
type t =
  | Var of Eva_ast.varinfo
  | HeapBlk of Cil_types.stmt (* block on the heap *)
  | InputMem

include Datatype.S with type t := t

module Set : Hptset.S with type elt = t
module Map (V : Datatype.S) : Hptmap_sig.S with type key = t and type v = V.t
module SetMap : Hptmap_sig.S with type key = t and type v = Set.t

module Util (_ : sig val ptr_targets : SetMap.t end) :
sig
  open Eva_ast_types

  val locs_of_lval : lval -> Set.t
  val locs_of_exp : exp -> Set.t
  val locs_of_nested_lval : lval -> Set.t
  val locs_of_deref : t -> Set.t
  val locs_of_init : init -> Set.t

  val recursive_locs : Set.t -> Set.t

  val typ_is_ptr : typ -> bool
end
