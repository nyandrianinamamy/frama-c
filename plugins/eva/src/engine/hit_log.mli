(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Hit log and result resolver (prototype).

    During an analysis, Eva records here the initialized globals and each
    invocation of a function: its callstack, its input after the binding of
    the arguments to the formals, and how it was interpreted. The analysis
    of a body also records its producer: the entries that survive the
    preconditions, possibly none, and the normalized states before and
    after each statement, the same states that the collection hooks of
    {!Cvalue_callbacks} receive. A memexec hit records the producer of the
    cache entry it uses.

    After the analysis, {!resolve} rebuilds the state at a control point on
    one callstack from these records, without reading the legacy result
    store. It rebuilds the state of each visit on the callstack, then joins
    the visits in the order of the analysis.

    The resolver only answers when the records are exact: the cvalue domain
    alone, all results recorded, no multithread analysis, and an analysis
    that completed. It declines a request on a memexec hit, or below one,
    whose states it cannot rebuild yet. When it declines, the request reads
    the legacy store. The records are not saved with the project, and
    clearing the results of Eva invalidates them. *)

type state = Cvalue_domain.State.t

(** How Eva interpreted an invocation. *)
type kind =
  | Body of int
  (** Its body was analyzed; this invocation is the producer of this id. *)
  | Hit of int
  (** A memexec hit on the cache entry of the producer of this id. *)
  | Spec_or_builtin
  (** A specification or a builtin, or a body whose analysis did not
      record its producer. *)

(** {2 Recording} *)

(** [start ~exact] starts the records of a new analysis. Nothing is
    recorded unless [exact]. *)
val start: exact:bool -> unit

(** Marks the records as complete, once the analysis has completed. *)
val seal: unit -> unit

(** Whether the current analysis records. *)
val recording: unit -> bool

(** [initial callstack state]: the initialized globals, before the binding
    of the formals of the entry point. *)
val initial: Callstack.t -> state -> unit

(** [enter callstack input] opens an invocation, whose input is the state
    after the binding of the arguments to the formals. *)
val enter: Callstack.t -> state -> unit

(** [leave callstack] closes the innermost open invocation. *)
val leave: Callstack.t -> unit

(** [hit callstack ~producer]: the open invocation on [callstack] is a
    memexec hit. *)
val hit: Callstack.t -> producer:int -> unit

type points = {
  before: state Cil_datatype.Stmt.Hashtbl.t;
  after: state Cil_datatype.Stmt.Hashtbl.t;
}

(** [body callstack ~producer ~entries ~points]: the open invocation on
    [callstack] analyzed its body. [entries] are the states that survive the
    preconditions; [points] are the states before and after each statement,
    or [None] if the results of the function are not recorded. *)
val body:
  Callstack.t -> producer:int -> entries:state list ->
  points:points Lazy.t option -> unit

(** {2 Resolver} *)

(** [resolve ~callstack point] rebuilds the state at [point] on [callstack]
    from the records: [`Bottom] if no visit reaches the point, [`Top] if the
    results of the function are not recorded. Returns [None] when the
    resolver declines. *)
val resolve:
  callstack:Callstack.t -> Domain_store.control_point ->
  state Lattice_bounds.or_top_bottom option

(** Prints the visits recorded on a callstack: their kind, their input, and
    the number of entries that survive the preconditions. *)
val pretty_visits: Format.formatter -> Callstack.t -> unit

(** Test control. When set, the resolver rebuilds each body visit from the
    first producer recorded for its function instead of its own. *)
val set_wrong_producer_control: bool -> unit
