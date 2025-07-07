(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

type options = {
  enabled: bool;
  dist_limit: int;
  interproc: bool;
  include_guards: bool;
  required_writes: int;
}

type result = private {
  split_v: unit Vertex.Hashtbl.t;
  merge_e: vertex Datatype.Int.Hashtbl.t;
  call_merge_e: Cil_types.stmt Datatype.Int.Hashtbl.t;
}

val get_result : options -> Cil_types.kernel_function -> result
(** [get_result options kf] returns, for function [kf], the partitioning
    information. *)
