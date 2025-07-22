(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

(** A memory access *)
type mem_access =
  | Reads of Basic_locations.t
  (** The reading of a location *)
  | Writes_to of Basic_locations.t * bool
  (** The writing of a location; the boolean indicates if it's a partial
      write *)

val compute_edge_accesses :
  graph -> Cil_types.varinfo list option ->
  Basic_analysis.lw_and_pt Vertex.Hashtbl.t -> mem_access list Edge.Hashtbl.t
(** [compute_edge_accesses graph interproc_args states] computes and returns the
    memory accesses happening at each edge of [graph]. [states] are used to know
    pointer targets. [interproc_args] must be the list of arguments of the
    function, but only in interprocedural mode, so that their pointer targets
    may, or not, be considered as read by the return statement. *)
