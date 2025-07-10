(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

type mem_access =
  | Reads of Basic_locations.t
  | Writes_to of Basic_locations.t * bool
  (* the boolean indicates if it's a partial write *)

val compute_edge_accesses :
  graph -> Cil_types.varinfo list option ->
  Basic_analysis.lw_and_pt Vertex.Hashtbl.t -> mem_access list Edge.Hashtbl.t
