(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Access to other plugins API via {!Dynamic.get}. *)

module Inout: sig
  (** Registers a hook to be called on the inputs/outputs computed by the Inout
      plugin for each function call. *)
  val register_call_hook: (Inout_type.t -> unit) -> unit

  (** Registers a hook to be called, for each call analysed by its body, on
      the function that gives the memory read or written on the paths from the
      start of the body to the point before and to the point after each
      statement. Nothing is done if the inout plugin is missing. *)
  val register_footprint_hook:
    ((Cil_types.stmt -> Memory_zone.t * Memory_zone.t) -> unit) -> unit

  (** Returns the memory zone modified by the given function (including local
      and formal variables). Returns Top if the inout plugin is missing. *)
  val kf_outputs: Kernel_function.t -> Memory_zone.t
end

module Callgraph: sig
  (** Iterates over all functions in the callgraph in reverse order, i.e. from
      callees to callers. If callgraph is missing or if the number of callsites
      is too big, the order is unspecified. *)
  val iter_in_rev_order: (Kernel_function.t -> unit) -> unit
end

module Scope: sig
  (** Removes redundant assertions. Warns if the scope plugin is missing. *)
  val rm_asserts: unit -> unit
end
