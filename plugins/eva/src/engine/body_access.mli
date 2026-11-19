(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Observations made while Eva analyses a call by its body. *)

module Result : sig
  (** Reasons to refuse storage, in the order used to select the reason of
      the storage disposition. [Reallocation], [Allocation] and
      [Deallocation] are performed by the allocation builtins, including
      the deallocation of the automatic blocks of a call at its return.
      [Validity_mutation] is an update of the validity record of an
      allocated block, also by the widening of a memory map.
      [Allocated_block] is an allocated block among the blocks accessed, the
      locations computed or the blocks designated by a value.
      [Allocation_metadata] is a read of the validity or of the type of an
      allocated block, also by an operation of the analyzer that the
      program does not select. A body inherits these six reasons from the
      bodies analysed during its own analysis. *)
  type refusal =
    | Indirect_call
    | Reallocation | Allocation | Deallocation | Validity_mutation
    | Builtin | Sweep | Contract | Annotation | Nested_call
    | Allocated_block | Allocation_metadata | Footprint_top | Side_table

  val refusal_id : refusal -> string

  type recorded =
    | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

  type t = {
    reads : Base.SetLattice.t;
    writes : Base.SetLattice.t;
    exit_writes : Base.SetLattice.t;
    sure_writes : Base.Hptset.t;
    designated : Base.SetLattice.t;
    owners : Base.Hptset.t;
    recorded : recorded list;
    refusals : refusal list;
  }
  (** May sets can be [Top] when an unsupported operation has unknown
      accesses. The sure set contains only fully overwritten blocks.
      [owners] holds the allocated blocks whose validity or type was read,
      including by the bodies analysed during the analysis of this one. *)

  (** Observe an immutable result after a completed analysis of a body and
      before the storage verdict. Requires [-eva-cache-collect].
      Observers must not change the analysis. *)
  val on_result : (Callstack.t -> t -> unit) -> unit
end

val capture : Callstack.t -> (unit -> 'a) -> 'a * Result.t option
val without_recording : (unit -> 'a) -> 'a
(** Runs a function outside the observation of the current body. *)

val at_call_site : (unit -> 'a) -> 'a
(** Runs a function that belongs to the call site of the current body, as
    the check of its [requires] clauses. Only the reasons of the allocation
    family are recorded, with [Footprint_top]: the allocated blocks among
    the blocks read and designated, including through {!read_bases},
    {!designate_bases} and {!designate_cells}, the reads of allocation
    metadata with their owners, and the allocation effects. A set of blocks
    that is [Top] refuses with [Footprint_top]. The blocks are not added to
    the sets of the body. *)

val is_recording : unit -> bool

(** Whether a body or the call site of a body is observed. *)
val is_observing : unit -> bool
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

(** [weakened base] records that [base], strong until now, becomes weak.
    The record lasts as long as the bases of the program. *)
val weakened : Base.t -> unit

(** Refuses with [Allocation_metadata] before the tags of the nodes of
    offsetmaps are consulted, when a block has been made weak: a node keeps
    the tag computed at its first construction, which depends on the
    weakness of the blocks its value designates. The weakened blocks become
    owners. *)
val read_node_tags : unit -> unit

val transfer :
  id:int -> src:int -> dst:int -> ('a -> 'b list) -> 'a -> 'b list

(** [check_written ~entry ~exits] checks the contents, in the entry state
    and in each exit state of the current body, of every block that the
    body may write. A value that designates an allocated block refuses with
    [Allocated_block] and adds the block to the owners; an unknown set of
    blocks refuses with [Footprint_top]. An unknown set of written blocks
    is not checked: each unknown write comes with its own refusal. The
    analysis of the body builds,
    joins, narrows and widens the offsetmaps of these blocks, and the
    kernel can use a memoised result there without reading the metadata of
    the blocks that their values designate. *)
val check_written : entry:Cvalue.Model.t -> exits:Cvalue.Model.t list -> unit

val finish_paths : entry:int -> exit:int -> returns:bool -> unit
