(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** The Reach part of a cache entry: the statements that the analysis of a
    body reaches, and the other writes of the analysis into tables that
    describe where the analysis went.

    Each write is a join into a table of Eva: a state saved at a control
    point for a callstack (the store of states joins the states saved at the
    same point for the same callstack), a guard outcome (a bit set to true
    by the first edge taken), the read and written zones at a position (a
    union), and the call site of a function (a union). While Eva analyses a
    body through {!capture}, the writes of the body are recorded with the
    statement and the callstack they belong to. A hit on an entry delivers
    them again for its own callstack (see {!Reach_delivery}).

    A write is recorded under the same conditions as the writes of the
    Safety part ({!Safety_part}): only while the collector of block
    accesses observes the body itself, and not during the checks of the
    [requires] clauses of the called function. A write of a body analysed
    during the analysis of another one is recorded in the inner body only.
    A write made after a change of the current project is not recorded, and
    refuses the body as [Project_switch]. *)

open Cil_types

(** The calls between a body and the callstack of a write, the innermost
    call first: the empty list for a write made by the body itself (see
    {!Safety_part.frames}). *)
type frames = Callstack.call list

type write =
  | Reached of { point : Domain_store.control_point; frames : frames }
  (** A state is saved at [point] for the callstack of the write: [point]
      is reached in this callstack. [point] is [Start], [Before] or
      [After]. *)
  | Guard of { stmt : stmt; outcome : bool }
  (** The branch [outcome] of the condition of [stmt] is taken: the
      [then] branch when [outcome] is true, the [else] branch otherwise
      (see {!Iterator.condition_truth_value}). The table has no callstack
      dimension. *)
  | Zones of {
      stmt : stmt;
      frames : frames;
      read : Memory_zone.t;
      write : Memory_zone.t;
    }
  (** The zones read and written at [stmt] in the callstack of the write
      (see {!Inout_access}): the join of every registration made there by
      the body. *)
  | Caller of { frames : frames }
  (** The function called by the innermost call of [frames] is called from
      its call site (see {!Function_calls}). [frames] is never empty: the
      call site of the body itself belongs to its caller. *)

(** The writes of a body, in the order of their first emission. Each write
    is kept once: emitting it again changes no table. The zones of a
    statement in a callstack are joined into one write. *)
type t = write list

val empty : t

(** [reroot callstack frames] is the callstack of a write with [frames]
    made by a body called with [callstack]. *)
val reroot : Callstack.t -> frames -> Callstack.t

val pretty_write : Format.formatter -> write -> unit
val pretty : Format.formatter -> t -> unit

(** [capture callstack analyse] runs [analyse], the analysis of a body
    called with [callstack], and returns its result with the writes
    recorded meanwhile. Captures can be nested: a write is recorded in the
    innermost one. The writes are passed to the functions registered by
    {!on_result} before being returned. *)
val capture : Callstack.t -> (unit -> 'a) -> 'a * t

(** Observe the writes of each body after its analysis, before the
    storage decision, for a body whose storage is refused as for one that
    is stored. Observers must not change the analysis. *)
val on_result : (Callstack.t -> t -> unit) -> unit

(** {2 Recording}

    The functions below record a write. They do nothing outside a capture
    or outside the observation of the body. A write whose callstack is not
    the callstack of the body or one of its extensions cannot be delivered
    at another callstack: it refuses the body as [Side_table]. *)

(** [record_state callstack point] records that a state is saved at
    [point] for [callstack]. Nothing is recorded for [Initial]. *)
val record_state : Callstack.t -> Domain_store.control_point -> unit

(** [record_guard stmt outcome] records that the branch [outcome] of the
    condition of [stmt] is taken. *)
val record_guard : stmt -> bool -> unit

(** [record_zones position ~read ~write] records that [read] and [write]
    are joined to the zones of [position]. *)
val record_zones :
  Position.t -> read:Memory_zone.t -> write:Memory_zone.t -> unit

(** [record_caller callstack] records the call site of the top function of
    [callstack]. *)
val record_caller : Callstack.t -> unit
