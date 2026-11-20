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
  (** Log every read, and abort Eva on each read in one of these phases.
      The trap has no exemption and stays armed: the first trapped read
      aborts Eva with its description, and each later trapped read raises
      the same exception again, without a new message. A reader that
      catches the exception therefore does not disarm the guard. *)

(** Every phase, in the order of an execution. [Trap all_phases] traps every
    read from the moment it is armed. *)
val all_phases: phase list

(** Phases and readers are only tracked while the guard is armed: arm it
    before running the analysis. Arming the guard clears {!forbid}. *)
val arm: mode -> unit
val mode: unit -> mode

(** The modes armed since the start of the process, in order. Not cleared by
    {!clear}: it shows whether a run changed the mode of the guard. *)
val arm_history: unit -> mode list

(** [forbid labels] traps the reads made on behalf of the readers [labels],
    in addition to the mode, while the guard is armed: each read whose
    enclosing readers include one of [labels] aborts Eva, in any phase, as a
    read trapped by the mode does. *)
val forbid: string list -> unit

(** [during phase f] runs [f] in [phase]. While the guard is armed, each
    call counts as an entry of [phase]. *)
val during: phase -> (unit -> 'a) -> 'a

(** The current phase, while the guard is armed; [Request] otherwise. *)
val phase: unit -> phase

(** The number of entries of each phase since the last {!clear}, while the
    guard was armed, in the order of {!all_phases}. *)
val phase_entries: unit -> (phase * int) list

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

(** The first read that triggered the trap since the last {!clear}, if
    any. *)
val trapped: unit -> read option

(** The number of trapped reads since the last {!clear}: the first one and
    those that raised the exception again. *)
val trapped_count: unit -> int

(** {2 Resolutions}

    The resolver of {!Hit_log} answers some requests without reading the
    legacy store. The guard logs each answer as a resolution, separately
    from the reads, so that a request shows which path served it. *)

type resolution = {
  resolved_phase: phase;
  resolved_point: string;
  (** The control point and callstack. *)
  visits: string;
  (** The invocations used, with their kind and producer. *)
  resolved_readers: string list;
  (** Labels of the enclosing readers, outermost first. *)
}

(** [resolved point visits] is called by the resolver on each answer. The
    arguments are only used when the guard is armed. *)
val resolved:
  (Format.formatter -> unit) -> (Format.formatter -> unit) -> unit

(** Resolutions logged since the last {!clear}, in chronological order. *)
val resolutions: unit -> resolution list

(** [observe_resolutions f] runs [f] and also returns the resolutions logged
    during [f]. *)
val observe_resolutions: (unit -> 'a) -> 'a * resolution list

(** The outermost labelled reader, or ["unlabelled"]. *)
val reader_name: read -> string

(** The innermost labelled reader, or ["unlabelled"]. *)
val innermost_reader: read -> string

val phase_name: phase -> string
val phase_of_name: string -> phase option
val access_name: access -> string

(** Prints a read without its caller, whose name depends on the build. *)
val pretty_read: Format.formatter -> read -> unit
