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

module EdgeKeyTbl = Datatype.Int.Hashtbl

type result = private {
  split_v: unit Vertex.Hashtbl.t;
  merge_e: vertex EdgeKeyTbl.t;
  call_merge_e: Cil_types.stmt EdgeKeyTbl.t;
}

val compute : Cil_types.kernel_function -> options -> result
(** [compute kf options] returns, for function [kf], the partitioning
    information. *)
