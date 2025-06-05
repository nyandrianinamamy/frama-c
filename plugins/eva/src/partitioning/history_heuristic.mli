(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eva_automata

type options = {
  mode: [ `None | `Normal | `Enhanced | `Full ];
  interproc: bool;
}

type info = private {
  split_v : unit Vertex.Hashtbl.t;
  merge_e : vertex Datatype.Int.Hashtbl.t;
  call_merge_e : Cil_types.stmt Datatype.Int.Hashtbl.t;
}

val get_info : options -> Cil_types.kernel_function -> int -> info
(** [get_info mode kf dist_limit] returns, for function [kf], the
    partitioning information. *)
