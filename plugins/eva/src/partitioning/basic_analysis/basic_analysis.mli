(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module VtLocMap : Hptmap_sig.S
  with type key = Basic_locations.t and type v = Eva_automata.vertex

type lw_and_pt = VtLocMap.t * Basic_locations.SetMap.t

module LwAndPt (_ : sig val include_guards : bool end) :
sig
  include Eva_automata.Domain with type t = lw_and_pt

  val initial : Cil_types.varinfo list -> t
end
