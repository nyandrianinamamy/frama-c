(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module VtLocMap : Hptmap_sig.S
  with type key = Basic_locations.t and type v = Eva_automata.vertex

(** The type of states computed by the writes analysis: a pair of “last writes”
    and “pointer targets”. *)
type lw_and_pt = VtLocMap.t * Basic_locations.SetMap.t

(** The domain of the writes analysis. A state of this domain gives information
    about:
    - for each memory location, the last vertex at which it was written, or the
      last junction point at which branches gave it a value;
    - for each memory location that is a pointer, the set of memory locations it
      may point to.

    The “last writes” computation uses the “pointer targets” information. *)
module LwAndPt (_ : sig val include_guards : bool end) :
sig
  include Eva_automata.Domain with type t = lw_and_pt

  val initial : Cil_types.varinfo list -> t
  (** [initial args] returns the initial state, for the starting vertex of the
      automaton. *)
end
