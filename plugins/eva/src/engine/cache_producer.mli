(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Entries from fresh bodies. Only the supplied-entry fixture can make a
    produced entry a lookup candidate. *)

open Cil_types

type call_mode = [ `Body | `Spec | `Builtin ]
type entry

(** The current analysis's entries for a body, oldest first. They are
    cleared at the start of the next analysis and are not marshalled. *)
val entries : kernel_function -> entry list

(** Statement, closed key, filtered input, footprint and partitioned Exit
    part. *)
val cache_entry : entry -> Cache_entry.Cvalue.t

(** Classes of recorded joins seen while analysing the body. *)
val recorded : entry -> Body_access.Result.recorded list

(** The callstack in the current Eva results that holds the Inner part,
    when statement states were saved for this body. *)
val inner : entry -> Callstack.t option

(** Functions used by the analysis, with their call modes. Currently the
    collector admits only bodies that have no nested call. *)
val used_functions : entry -> (kernel_function * call_mode) list

type refusal =
  | Product | Collector of Body_access.Result.refusal
  | Footprint_top | Invalid_footprint | Relate_top | Key_limit
  | Preconditions | Not_cacheable | Input_state | Exit_state | Exit_binding

(** Stable identifier for diagnostics and statistics. *)
val refusal_id : refusal -> string

module Make (Domain : sig
    type t
    val structure : t Abstract.Domain.structure
  end) : sig
  (** Offer a completed body, with the collector result and verdict that
      belong to this analysis of the body. Returns the stored identifier or
      the reason for refusing storage. *)
  val store :
    save_results:bool -> Callstack.t -> Domain.t ->
    Domain.t Engine_sig.call_result -> Body_access.Result.t ->
    (unit, Body_access.Result.refusal) result -> (int, refusal) result
end
