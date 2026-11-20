(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Instrumentation of the reads of Eva's legacy result store (prototype).

    The legacy result store is made of the states recorded by
    {!Domain_store} at each control point, for each callstack, and of the
    per-function analysis status that tells whether these states exist.
    Every read of the store goes through {!notify}, whatever path the reader
    takes. The guard labels each read with the phase of the execution and
    with the readers that issued it. It then ignores, records or traps it,
    according to its mode.

    The mode and the log are plain references: they are not projectified,
    are not cleared with Eva's results, and arming the guard does not
    invalidate the analysis. *)

(** Phases of an execution. Reads made outside any Eva phase, before or
    after the analysis, are requests. *)
type phase =
  | Initialization  (** Computation of the initial state. *)
  | Analysis        (** Iteration over function bodies. *)
  | Collection      (** Hooks registered by other plugins with
                        {!Cvalue_callbacks}. *)
  | Post_analysis   (** Eva's passes after the iteration. *)
  | Request         (** Any other time. *)

type access =
  | Getter        (** A state at a control point. *)
  | Enumeration   (** The callstacks recorded at a control point. *)
  | Availability  (** Whether results are recorded. *)

type read = {
  phase: phase;
  access: access;
  store: string;
  (** The domain whose states are read, or ["analysis-status"]. *)
  point: string;
  (** The control point and callstack, if any. *)
  readers: string list;
  (** Labels of the enclosing readers, outermost first. *)
  caller: string option;
  (** The innermost stack frame outside Eva, the kernel and the standard
      library, unless the read comes from Eva's own analysis. Needs
      debugging information. *)
}

type mode =
  | Off
  | Record
  (** Log every read. *)
  | Trap of phase list
  (** Log every read, and abort Eva on the first read in one of these
      phases. The guard then falls back to [Record]. *)

(** Phases and readers are only tracked while the guard is armed: arm it
    before running the analysis. *)
val arm: mode -> unit
val mode: unit -> mode

(** [during phase f] runs [f] in [phase]. *)
val during: phase -> (unit -> 'a) -> 'a

(** [reader label f] runs [f] on behalf of the reader [label]. *)
val reader: string -> (unit -> 'a) -> 'a

(** [notify access ~store point] is called by the store on each read.
    [point] prints the control point and is only used when the guard is
    armed. *)
val notify: access -> store:string -> (Format.formatter -> unit) -> unit

(** Reads logged since the last {!clear}, in chronological order. *)
val reads: unit -> read list

val clear: unit -> unit

(** [observe f] runs [f] and also returns the reads logged during [f]. *)
val observe: (unit -> 'a) -> 'a * read list

(** The read that triggered the trap, if any. *)
val trapped: unit -> read option

(** The outermost labelled reader, or ["unlabelled"]. *)
val reader_name: read -> string

val phase_name: phase -> string
val phase_of_name: string -> phase option
val access_name: access -> string

(** Prints a read without its caller, whose name depends on the build. *)
val pretty_read: Format.formatter -> read -> unit
