(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Observations made while Eva analyses a call by its body. *)

module Result : sig
  type refusal =
    | Indirect_call | Builtin | Sweep | Contract | Annotation | Nested_call
    | Allocated_block | Footprint_top | Side_table

  val refusal_id : refusal -> string

  type recorded =
    | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

  type t = {
    reads : Base.SetLattice.t;
    writes : Base.SetLattice.t;
    exit_writes : Base.SetLattice.t;
    sure_writes : Base.Hptset.t;
    designated : Base.SetLattice.t;
    recorded : recorded list;
    refusals : refusal list;
  }
  (** May sets can be [Top] when an unsupported operation has unknown
      accesses. The sure set contains only fully overwritten blocks. *)

  (** Observe an immutable result after a completed analysis of a body and
      before the storage verdict. Requires [-eva-cache-collect].
      Observers must not change the analysis. *)
  val on_result : (Callstack.t -> t -> unit) -> unit
end

val capture : Callstack.t -> (unit -> 'a) -> 'a * Result.t option
val without_recording : (unit -> 'a) -> 'a
val is_recording : unit -> bool
val verdict : Result.t -> (unit, Result.refusal) result

val read : Locations.t -> unit

(** Same as [read], with the bases of the location computed by the caller. *)
val read_bases : Base.SetLattice.t -> unit
val write : Locations.t -> unit

(** Abstract binding updates provide possible writes without sure bits. *)
val may_write : Locations.t -> unit
val may_write_base : Base.t -> unit
val unknown_write : unit -> unit
val check_location : Cvalue.V.t -> unit
val designate : Cvalue.V.t -> unit

(** Records designated bases computed by the caller. *)
val designate_bases : Base.SetLattice.t -> unit

(** [designate_cells state loc] records the targets of the values stored in
    every cell of [state] that a load of [loc] may combine, before the
    combination. A location or state without known cells designates Top. *)
val designate_cells : Cvalue.Model.t -> Locations.t -> unit
val record : Result.recorded -> unit
val refuse : Result.refusal -> unit
val unknown_read : Result.refusal -> unit
val unknown_access : Result.refusal -> unit

(** Refuses as side-table before a message emitted once: emitting it reads
    the logger's history of emitted messages. *)
val read_message_history : unit -> unit

val transfer :
  id:int -> src:int -> dst:int -> ('a -> 'b list) -> 'a -> 'b list

val finish_paths : entry:int -> exit:int -> returns:bool -> unit
