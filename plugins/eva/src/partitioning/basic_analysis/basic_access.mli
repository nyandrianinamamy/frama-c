(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata
open Basic_locations
open Basic_analysis

type mem_access =
  | Reads of MemLoc.t
  | Writes_to of MemLoc.t * bool
  (* the boolean indicates if it's a partial write *)

val get_edge_accesses :
  automaton -> Cil_types.varinfo list option ->
  lw_and_pt Vertex.Hashtbl.t -> mem_access list Edge.Hashtbl.t
