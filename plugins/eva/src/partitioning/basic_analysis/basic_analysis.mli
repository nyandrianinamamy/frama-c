(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Basic_locations

type lw_and_pt = VMemLocMap.t * MlsMemLocMap.t

module LwAndPt (_ : sig val include_guards : bool end) :
sig
  include Eva_automata.Domain with type t = lw_and_pt

  val initial : Cil_types.varinfo list -> t
end
