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

type call_mode = Body_access.call_mode
type entry

(** The current analysis's entries for a body, oldest first. They are
    cleared at the start of the next analysis and are not marshalled. *)
val entries : kernel_function -> entry list

(** Statement, closed key, filtered input, footprint, partitioned Exit
    part, Safety part and Reach part. The Reach part is given when the
    states of the body were saved ([save_results]); otherwise its
    statements are not recorded as reached, and the entry has none. *)
val cache_entry : entry -> Cache_entry.Cvalue.t

(** Classes of recorded joins seen while analysing the body. *)
val recorded : entry -> Body_access.Result.recorded list

(** Targets of the admitted lexical sweeps. *)
val sweeps : entry -> Base.Hptset.t

(** The entry-time stamp when the body consulted dynamic widening hints. *)
val hint_generation : entry -> Widen_generation.t option

(** The callstack to query in the current Eva results when cvalue
    statement states were saved for this body. Queries join repeated visits
    to that callstack, so they can include states from other calls. *)
val inner : entry -> Callstack.t option

(** Functions used by the analysis, including transitive calls, with their
    call modes. *)
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
  (** Offer a completed body, with the Safety part, the Reach part, the
      collector result and the verdict that belong to this analysis of the
      body. Returns the stored entry or the reason for refusing storage. *)
  val store :
    save_results:bool -> safety:Safety_part.t -> reach:Reach_part.t ->
    Callstack.t -> Domain.t ->
    Domain.t Engine_sig.call_result -> Body_access.Result.t ->
    (unit, Body_access.Result.refusal) result ->
    (Cache_entry.Cvalue.t, refusal) result
end
