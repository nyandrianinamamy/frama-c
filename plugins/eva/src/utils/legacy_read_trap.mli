(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Test instrument: reports the reads of the legacy result store made after
    the iteration of an analysis, by the state requests of {!Results} and
    outside any request.

    The legacy result store is made of the tables of {!Domain_store}: for each
    domain, the states at each control point, joined over all callstacks and
    for each callstack. The instrument is told of every lookup of these
    tables, whatever the reader.

    A request is an access of {!Results} to the states at one control point:
    the joined state, or the states of some callstacks. It is reported if it
    starts while the instrument is on, after the iteration of an analysis of
    the current project: when Eva has results in this project, and from the
    end of the iteration to the setting of these results, while Eva is still
    computing. The iteration of an analysis lasts from its start to the end of
    the computation of the states, when the fixpoint returns; the hooks run
    when Eva has results and the passes that Eva runs afterwards, such as the
    summary, are outside it. The reads made by a request that starts during
    the iteration of an analysis of its project are not reported, only
    counted by {!ignored_reads}. A read made outside any request is reported
    apart, by {!stray_reads}, under the same conditions as a request. A lookup
    is a read only when the store of the domain has been saved: when the
    results of a domain are disabled, a request has no read of its store.

    The passes that Eva runs after the iteration are named: the requests and
    the reads outside any request made during a pass are reported with its
    name.

    Requests and analyses are followed by project: a request made in a
    project is reported even if the analysis of another project is running,
    and an analysis started within a request, or a request made in another
    project within a request, is not part of that request.

    The instrument is off by default and changes no result. The report is
    not projectified: it gathers the requests of all projects, and is
    neither saved nor changed with the current project. *)

(** What a read looks up in the store of one domain at one control point. *)
type access =
  | Joined
  (** The state joined over all callstacks. *)
  | Callstack of Callstack.t
  (** The state of one callstack. *)
  | Callstacks
  (** The callstacks that have a state. *)

type read = {
  store: string;
  (** The name of the domain whose store is read. *)
  access: access;
  point: string;
  (** The control point read. *)
}

(** A request reported by the instrument, with the reads it made. *)
type request = {
  number: int;
  (** Rank of the request among those reported since {!start}, from 1. *)
  description: string;
  (** The control point and the callstacks requested. *)
  pass: string option;
  (** The pass of Eva after the iteration during which the request was made,
      if any. *)
  reads: read list;
  (** In the order they were made. *)
}

(** A read reported outside any request. *)
type stray = {
  in_pass: string option;
  (** The pass of Eva after the iteration during which the read was made, if
      any. *)
  read: read;
}

(** Turns the instrument on, and empties its report. A request being served
    when [start] is called is left out of the new report, with the requests
    made within it and all their reads. *)
val start: unit -> unit

(** Turns the instrument off. Its report is kept. *)
val stop: unit -> unit

(** The requests reported since the last {!start}, in the order they were
    made, including those that read nothing. *)
val requests: unit -> request list

(** The reads reported outside any request since the last {!start}, in the
    order they were made. *)
val stray_reads: unit -> stray list

(** The number of reads made by requests that started during the iteration
    of an analysis, since the last {!start}. *)
val ignored_reads: unit -> int

val pretty_request: Format.formatter -> request -> unit

val pretty_stray: Format.formatter -> stray -> unit

(** Prints a callstack on one line. *)
val pretty_callstack: Format.formatter -> Callstack.t -> unit

(** {2 Used by Eva} *)

(** [analysis f] runs the iteration [f] of an analysis of the current
    project: requests that start meanwhile in this project are not reported,
    and their reads are counted by {!ignored_reads}. Eva sets its computation
    state to [Computing] within [f]: once [f] has returned, the requests and
    the reads are reported, even before Eva has results. *)
val analysis: (unit -> 'a) -> 'a

(** [pass name f] runs [f], the pass [name] that Eva runs after the
    iteration of an analysis of the current project. *)
val pass: string -> (unit -> 'a) -> 'a

(** [request pp f] serves by [f] the request printed by [pp]. Within another
    request of the same project, [f] is part of that request. *)
val request: (Format.formatter -> unit) -> (unit -> 'a) -> 'a

(** Whether the instrument is on and a read in the current project would be
    reported or counted: within a request, or after the iteration of an
    analysis of this project. Only then are reads signalled with {!read}. *)
val reading: unit -> bool

(** [read ~store access pp] signals a read of the store of domain [store] at
    the control point printed by [pp]. *)
val read: store:string -> access -> (Format.formatter -> unit) -> unit
