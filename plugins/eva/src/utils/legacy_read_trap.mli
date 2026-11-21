(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Test instrument: reports the reads of the legacy result store made while
    a state request of {!Results} is served after the analysis has ended.

    The legacy result store is made of the tables of {!Domain_store}: for each
    domain, the states at each control point, joined over all callstacks and
    for each callstack. The instrument is told of every lookup of these
    tables, whatever the reader.

    A request is an access of {!Results} to the states at one control point:
    the joined state, or the states of some callstacks. It is reported if it
    starts while the instrument is on, when Eva has results in the current
    project, and outside an analysis of this project. An analysis lasts from
    its start to the end of the passes that Eva runs after the iteration,
    such as the summary. The reads made by a request that starts during an
    analysis of its project are not reported, only counted by
    {!ignored_reads}. The reads made outside any request, by the analysis or
    by other readers of the store, are neither reported nor counted. A lookup
    is a read only when the store of the domain has been saved: when the
    results of a domain are disabled, a request has no read of its store.

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
  reads: read list;
  (** In the order they were made. *)
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

(** The number of reads made by requests that started during an analysis,
    since the last {!start}. *)
val ignored_reads: unit -> int

val pretty_request: Format.formatter -> request -> unit

(** Prints a callstack on one line. *)
val pretty_callstack: Format.formatter -> Callstack.t -> unit

(** {2 Used by Eva} *)

(** [analysis f] runs the analysis [f] of the current project: requests that
    start meanwhile in this project are not reported. *)
val analysis: (unit -> 'a) -> 'a

(** [request pp f] serves by [f] the request printed by [pp]. Within another
    request of the same project, [f] is part of that request. *)
val request: (Format.formatter -> unit) -> (unit -> 'a) -> 'a

(** Whether a request is being served in the current project while the
    instrument is on. Only then are reads signalled with {!read}. *)
val reading: unit -> bool

(** [read ~store access pp] signals a read of the store of domain [store] at
    the control point printed by [pp]. *)
val read: store:string -> access -> (Format.formatter -> unit) -> unit
