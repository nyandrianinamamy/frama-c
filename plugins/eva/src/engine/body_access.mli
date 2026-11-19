(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Observations made while Eva analyses a call by its body. *)

type call_mode = Cache_observation.call_mode

type call_trace = {
  functions : (Cil_types.kernel_function * call_mode) list;
  recursive : bool;
}

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
      bodies analysed during its own analysis.
      [Project_switch] is a change of the current project during the
      recording, by a callback for instance, even if the project changes
      back before its end: the recording belongs to the project current
      when it started, and the observations made in another project are not
      sorted out. Each recording in progress at the change is refused, the
      bodies whose analysis contains that of the current one included. *)
  type refusal =
    | Project_switch
    | Indirect_call
    | Reallocation | Allocation | Deallocation | Validity_mutation
    | Recursion | Watchpoint | Dump
    | Builtin | Threaded | Sweep | Widening_hint | Stop_at_alarm
    | Callback | Trace_id | Contract | Annotation | Nested_call
    | Allocated_block | Allocation_metadata | Footprint_top | Side_table

  val refusal_id : refusal -> string

  type recorded = Cache_observation.recorded =
    | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

  type t = {
    reads : Base.SetLattice.t;
    dependencies : Base.SetLattice.t;
    writes : Base.SetLattice.t;
    exit_writes : Base.SetLattice.t;
    sure_writes : Base.Hptset.t;
    designated : Base.SetLattice.t;
    owners : Base.Hptset.t;
    sweeps : Base.Hptset.t;
    used_functions : (Cil_types.kernel_function * call_mode) list;
    hint_generation : Widen_generation.t option;
    recorded : recorded list;
    refusals : refusal list;
    children : Cache_observation.child list;
  }
  (** May sets can be [Top] when an unsupported operation has unknown
      accesses. [dependencies] bounds the values read from the body input.
      The sure set contains only fully overwritten blocks.
      [children] records the fresh entries produced or the supplied entries
      used at the call sites of this body. The referenced entries own their
      own children.
      [owners] holds the allocated blocks whose validity or type was read,
      including by the bodies analysed during the analysis of this one.
      [sweeps] contains the targets of observed own-local sweeps.
      [used_functions] includes the body and the functions seen during
      nested work, with their modes, including a hit's producing trace
      when available.
      [hint_generation] is the entry-time stamp when a widening read ran. *)

  (** Numeric generation within the analysis, starting at zero. *)
  val hint_generation_number : Widen_generation.t -> int

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
    the check of its [requires] clauses. A nested check is recorded in the
    caller. In the callee's result, only the reasons of the allocation
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

(** Registers an exact lexical sweep of the current body's own inner locals.
    Returns whether to report the holders rewritten by that sweep. *)
val sweep :
  owner:Cil_types.kernel_function -> inner:bool -> Base.Hptset.t ->
  Cvalue.Model.t -> bool

(** Records the read and possible write of a cell rewritten by a sweep. *)
val swept_holder : Base.t -> Cvalue.V.t -> unit

(** [weakened base] records that [base], strong until now, becomes weak.
    The record lasts as long as the bases of the program. *)
val weakened : Base.t -> unit

(** Refuses with [Allocation_metadata] before the tags of the nodes of
    offsetmaps are consulted, when a block has been made weak: a node keeps
    the tag computed at its first construction, which depends on the
    weakness of the blocks its value designates. The blocks recorded by
    {!weakened} become owners. A validity record made weak without
    {!weakened}, counted by [Base.weakenings], refuses with no owner. *)
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


(** Run alternative transfers from the same recorded prefix. Only results
    accepted by [continues] contribute to the edge's exit writes. Their
    possible writes are joined and their sure bits intersected. All reads
    and prefix writes are recorded, including on stopped paths. *)
val map_alternatives :
  continues:('b -> bool) -> ('a -> 'b) -> 'a list -> 'b list

(** Records a resolved nested invocation, including one answered by memexec.
    A fresh child additionally contributes its own observed callees. *)
val call : Cil_types.kernel_function -> call_mode -> unit

(** Includes the producing trace of a hit in the enclosing recording.
    [stack] is the stack of the call that hit. *)
val include_trace : Callstack.t -> call_trace -> unit

(** Whether the current function or any recorded used function occurs below
    the current call in [stack]. *)
val recursion_conflict :
  Callstack.t -> (Cil_types.kernel_function * call_mode) list -> bool

(** Records that the current body consulted the dynamic hint table. *)
val read_widening_hints : unit -> unit
(** Scope the callee's ephemeral blocks while evaluating a call. They can
    appear in prefix reads and writes but cannot survive the call. *)
val with_callee :
  Cil_types.kernel_function -> Cil_types.varinfo option -> (unit -> 'a) -> 'a

(** Compose a fresh body result and retain its entry if one was produced. *)
val include_fresh :
  Callstack.t -> Result.t -> Cache_observation.reference option -> unit

(** Compose the winning supplied entry at the current call site. *)
val include_hit :
  Callstack.t -> Cache_observation.reference ->
  footprint:Cache_observation.footprint -> key:Base.Hptset.t -> returns:bool ->
  sweeps:Base.Hptset.t -> hint_generation:Widen_generation.t option ->
  functions:(Cil_types.kernel_function * call_mode) list ->
  observation:Cache_observation.observation option -> unit
