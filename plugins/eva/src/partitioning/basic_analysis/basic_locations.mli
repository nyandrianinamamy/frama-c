(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

module MemLoc :
sig
  type elt =
    | Var of Eva_ast.varinfo
    | HeapBlk of Cil_types.stmt (* block on the heap *)
    | InputMem

  include Hptmap.Id_Datatype with type t = elt
  include Hptset.Info with type elt := elt
  include Datatype.S_with_collections with type t := elt
end

module MemLocSet : Hptset.S with type elt = MemLoc.elt
module VMemLocMap : Hptmap_sig.S with type key = MemLoc.elt and type v = vertex
module MlsMemLocMap :
  Hptmap_sig.S with type key = MemLoc.elt and type v = MemLocSet.t

module MemLocUtil (_ : sig val ptr_targets : MlsMemLocMap.t end) :
sig
  open Eva_ast_types

  val locs_of_lval : lval -> MemLocSet.t
  val locs_of_exp : exp -> MemLocSet.t
  val locs_of_nested_lval : lval -> MemLocSet.t
  val locs_of_deref : MemLoc.elt -> MemLocSet.t
  val locs_of_init : init -> MemLocSet.t

  val recursive_locs : MemLocSet.t -> MemLocSet.t

  val typ_is_ptr : typ -> bool
end
