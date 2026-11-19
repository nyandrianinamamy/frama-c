(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** The Safety part of a cache entry: the alarms, the property statuses and
    the red contexts that the analysis of a body emits.

    Each of them is a write into a table of the kernel or of Eva, and each
    write is a join: the kernel combines a status with the statuses that
    the same emitter emitted before on the same property, and a red context
    adds a callstack to a set. While Eva analyses a body through
    {!capture}, the writes of the body are recorded with the statement, the
    emitter and the callstack they belong to. A hit on an entry delivers
    them again for its own callstack (see {!Safety_delivery}).

    A write is recorded only while the collector of block accesses observes
    the body itself ({!Body_access.is_recording}): the checks of the
    [requires] clauses of the called function, which belong to the call
    site, and the callbacks run without recording are not part of the body.
    A write of a body analysed during the analysis of another one is
    recorded in the inner body only.

    A recording belongs to the project that is current when it starts. A
    write made while another project is current is not recorded, and
    refuses the body as [Project_switch] (see {!Body_access}). *)

open Cil_types

(** The calls between a body and the callstack of a write, the innermost
    call first: the empty list for a write made by the body itself. *)
type frames = Callstack.call list

(** What a red context is about: an alarm or a property. *)
type red_target = Alarm of Alarms.t | Prop of Property.t

type write =
  | Emitted_alarm of {
      kinstr : kinstr;
      alarm : Alarms.t;
      status : Property_status.emitted_status;
      emitter : Emitter.t;
      frames : frames;
    }
  (** [Alarms.register ~status emitter kinstr alarm]: the alarm is added as
      an assertion at [kinstr], if new, and [status] is emitted on it. *)
  | Emitted_status of {
      property : Property.t;
      status : Property_status.emitted_status;
      emitter : Emitter.t;
      frames : frames;
    }
  (** [Property_status.emit ~distinct:true emitter ~hyps:[] property
      status]. *)
  | Status_message of {
      status : Property_status.emitted_status;
      loc : Fileloc.t;
      stacktrace : bool;
      text : string;
      frames : frames;
    }
  (** The message that reports a status of a property evaluated by the
      body, printed by {!status_message}. *)
  | Red_context of {
      kinstr : kinstr;
      target : red_target;
      count : int;
      frames : frames;
    }
  (** The callstack of the write is among those in which [target] got a red
      status at [kinstr] (see {!Red_statuses}): at least one visit of the
      body in this callstack violates [target]. [count] is the number of
      times the body set this red status in this callstack; the hooks of
      {!Red_statuses} run once for each. *)

(** The writes of a body, each once, in the order of their first
    emission. Two red contexts that differ only by their count are the same
    write, whose count is the sum of theirs. *)
type t = write list

val empty : t

val frames : write -> frames

(** [reroot callstack frames] is the callstack of a write with [frames] made
    by a body called with [callstack]. *)
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

    The functions below record a write with the current callstack
    ({!Current_callstack.get}). They do nothing outside a capture or
    outside the observation of the body. A write whose callstack is not
    the callstack of the body or one of its extensions cannot be delivered
    at another callstack: it refuses the body as [Side_table]. *)

val record_alarm :
  kinstr -> Alarms.t -> Property_status.emitted_status -> Emitter.t -> unit

(** [record_red_context ~count kinstr target] records that the red status
    of [target] at [kinstr] was set [count] times, 1 by default. *)
val record_red_context : ?count:int -> kinstr -> red_target -> unit

(** [emit_status emitter property status] records the write and emits
    [status] on [property], as {!Emitted_status} describes. *)
val emit_status :
  Emitter.t -> Property.t -> Property_status.emitted_status -> unit

(** [status_message status ~loc ~stacktrace text] records the write and
    prints [text] once at [loc]: as a result of the message category
    [progress] when [status] is [True], as a warning of the category
    [alarm] otherwise. With [stacktrace] and the message category
    [callstacks], the current callstack follows the text. Eva prints the
    messages of the statuses that a body establishes through it, and a hit
    prints those of its entry through it again, so that the action of the
    category and the rule of printing a text once apply to both. *)
val status_message :
  Property_status.emitted_status -> loc:Fileloc.t -> stacktrace:bool ->
  string -> unit
