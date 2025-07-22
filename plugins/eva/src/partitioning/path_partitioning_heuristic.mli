(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

(** Options for the heuristic **)
type options = {
  (** If it is not enabled, return empty tables *)
  enabled: bool;
  (** The number of junction points to cross before stopping *)
  dist_limit: int;
  (** If partitioning should sometimes persist after return *)
  interproc: bool;
  (** If guards must be counted as writes *)
  include_guards: bool;
  (** The number of required writes to enable partitioning *)
  required_writes: int;
}

module EdgeKeyTbl = Datatype.Int.Hashtbl

(** The tables computed by the heuristic, which should direct partitioning *)
type result = private {
  (** The vertices at which splitting must be done *)
  split_v: unit Vertex.Hashtbl.t;
  (** The edges after which merging must be done *)
  merge_e: vertex EdgeKeyTbl.t;
  (** The edges after which merging the branches of a call should be done *)
  call_merge_e: Cil_types.stmt EdgeKeyTbl.t;
}

val compute : Cil_types.kernel_function -> options -> result
(** [compute kf options] returns, for function [kf], the partitioning
    information. *)
