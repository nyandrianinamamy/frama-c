(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Parts of cache entries owned by other modules.

    A module that keeps its own result for each call analysed by Eva, such
    as the callwise results of From and Inout, declares a part with
    {!register}: its name, whether a consumer of the part is enabled in the
    current analysis, and how to restore the part at a hit. The module keeps
    its own computation: at the end of each fresh analysis of a body, it
    computes its result as before and gives it to the cache with {!provide}.

    The cache keeps the parts given during the analysis of a body with the
    entry produced from this analysis, if any (see {!Cache_producer}). A
    hit of the reuse operation on an entry restores each part of the entry
    whose consumer is enabled, through the function given to {!register},
    in the order of registration. A candidate entry that lacks a part whose
    consumer is enabled is rejected (see {!Cache_entry.rejection}), and the
    call is analysed afresh when no other candidate matches.

    A hit of memexec restores no part: its consumers resolve the identifier
    sent with [`Reuse] to {!Cvalue_callbacks} against their own tables.
    Conversely, a hit of the reuse operation sends no [`Reuse] results to
    {!Cvalue_callbacks}: its identifier is not one of memexec. *)

open Cil_types

(** A part whose values have type ['a]. *)
type 'a t

(** [register ~name ~needed ?audited ~restore ()] declares a part named
    [name].
    - [name] identifies the part in the messages and in {!names}. Raises
      [Invalid_argument] if a part of the same name is already registered.
    - [needed ()] tells whether a consumer of the part is enabled in the
      current analysis. While it holds, a hit needs the part. It must not
      change during an analysis.
    - [restore callstack kf pre value] restores [value], the part of the
      entry used by a hit at a call of [kf] with [callstack], whose cvalue
      state at the start of the call is [pre]. It is called at the place
      where the fresh analysis of the body sends its results to the hooks
      of {!Cvalue_callbacks}, after the call hooks with [`Reuse], the check
      of the preconditions and the delivery of the Safety part of the entry
      ({!Safety_delivery}), and before the caller uses the states at the end
      of the call. The collector of block accesses does not observe
      it. It must return normally: an exception that it raises stops the
      analysis, after the writes that this function and the restoration of
      the parts registered before it have made, which are not undone.
    - [audited ()] holds when [restore] and every client that it runs have
      been audited for the cache: given the value kept with the entry, they
      write what the analysis of the body writes in the state of the call,
      and nothing that follows depends on whether a hit answered the call.
      While a part whose consumer is enabled is not audited, the lookup
      rejects every supplied entry (see {!Supplied_entries}). Default:
      never.

    [needed] and [audited] are predicates: each lookup with candidates
    evaluates them once, before its test of the clients that are not
    audited ({!decide}), and the check of the parts and the restoration use
    these answers. A predicate must return a result, without an exception;
    it must not register anything, a client of a hook or a part included,
    and must not write in the tables of the analysis or of the kernel. A
    client that it registers all the same on a hook listed under
    [`Callback] in {!Supplied_entries} is seen by the test of the lookup
    that evaluates it, and a part that it registers makes this lookup
    reject its candidates with [`Callback].

    Parts are registered when their owner is loaded, before any analysis. *)
val register :
  name:string -> needed:(unit -> bool) -> ?audited:(unit -> bool) ->
  restore:(Callstack.t -> kernel_function -> Cvalue.Model.t -> 'a -> unit) ->
  unit -> 'a t

val name : 'a t -> string

(** [provide part callstack ~reads value] gives [value] as the part computed
    by the fresh analysis of the body called with [callstack]. It must be
    called during this analysis, after the analysis of the calls made by the
    body: for instance from a hook of {!Cvalue_callbacks} that receives the
    [`Body] results of the call. The value is kept when the innermost body
    being analysed through the cache is called with [callstack] and when the
    current project is the one in which its analysis started. Otherwise it
    is dropped, and the entry produced from this analysis lacks the part. A
    second value given for the same part and the same analysis replaces the
    first.

    [reads] holds every block whose value, in the states of this call at
    the statements of the body or at its start, the computation of [value]
    read, the blocks read to compute an address included; [Top] when they
    are not known. A hit restores [value] in place of a computation from the
    states of the call of the hit, which agree with those of this call on
    the key of the entry only. The entry keeps the part only when every
    block of [reads] is in its key or is a local variable of the body (see
    {!cover}). Besides these states, the computation may read only what is
    the same for every call: the options and the initial state of the
    analysis, or the results of the analysis ({!Results}), which are not
    available while it runs and answer [Top]. It must not read what the
    other calls of the analysis have recorded. *)
val provide : 'a t -> Callstack.t -> reads:Base.SetLattice.t -> 'a -> unit

(** [register_state_reader ~name reads] declares a consumer that reads the
    states that Eva saves at the statements of the functions, while
    [reads ()] holds in the current analysis. A hit saves no state at the
    statements of the called function, and no part restores them: while a
    declared reader reads, every candidate entry is rejected. A reader that
    is not declared, or that reads later than the analysis without having
    declared it, is not detected. [reads] is a predicate under the rules
    given at {!register}: a lookup evaluates it before its test of the
    clients that are not audited. *)
val register_state_reader : name:string -> (unit -> bool) -> unit

(** {2 For the cache} *)

(** The parts kept with one entry. *)
type parts

(** No part. *)
val empty : parts

(** The names of the parts, in the order of registration. *)
val names : parts -> string list

(** The value of a part, if present. *)
val find : 'a t -> parts -> 'a option

(** [capture callstack analyse] runs [analyse], the fresh analysis of a body
    called with [callstack], and returns its result with the parts given by
    {!provide} meanwhile. Captures can be nested. The parts given during an
    analysis that raises an exception are dropped. *)
val capture : Callstack.t -> (unit -> 'a) -> 'a * parts

(** [cover kf ~key parts] keeps the parts of [parts] whose reads (see
    {!provide}) are covered by [key], the key of the entry produced from the
    analysis of the body of [kf]: each block read is in [key] or is a local
    variable of [kf], other than a formal. The values of these blocks at the
    statements of the body depend only on the blocks of the key in the state
    at the start of the call. The other parts are withheld, with the
    reason {!uncovered_read}. *)
val cover : kernel_function -> key:Base.Hptset.t -> parts -> parts

(** [uncovered-read], the reason why {!cover} withholds a part. *)
val uncovered_read : string

(** Whether a reader declared by {!register_state_reader} reads in the
    current analysis, or a plug-in that requests the results by function of
    From or Inout is loaded. These results are computed from the states
    saved at the statements of each function, those of the called functions
    included. The rule is by dependency: Pdg, Reduc and Studia are named,
    and a plug-in that loads one of them is covered by it, as Impact, Scope,
    Security-slicing, Slicing and Sparecode, which load Pdg. A request made
    after the analysis is not seen here: From and Inout refuse it when
    {!Eva.Results.statement_results_complete} is false. *)
val reads_statement_states : unit -> bool

(** The answers of the predicates [needed] and [audited] of the registered
    parts (see {!register}), taken once for one lookup. *)
type decisions

(** [decide ()] evaluates [needed] for every registered part, in the order
    of registration, and [audited] for those whose consumer is enabled.
    The lookup calls it once, before its test of the clients that are not
    audited, and passes the result to {!unaudited_clients}, {!supplies}
    and {!restoration}: no predicate runs between the test and the end of
    the delivery of a hit. *)
val decide : unit -> decisions

(** Whether, by [decisions], a part whose consumer is enabled is not
    audited (see {!register}), or a part was registered since the
    decisions were taken. *)
val unaudited_clients : decisions -> bool

(** Whether [parts] has every part whose consumer is enabled, by
    [decisions]. *)
val supplies : decisions -> parts -> bool

(** The parts that a hit restores, with their values. *)
type restoration

(** Nothing to restore. *)
val no_restoration : restoration

(** [restoration decisions parts] selects the parts of [parts] whose
    consumer is enabled by [decisions], in the order of registration.
    Raises [Invalid_argument] if one is missing: the lookup rejects such an
    entry ({!supplies}). *)
val restoration : decisions -> parts -> restoration

(** [restore callstack kf pre restoration] restores each part of
    [restoration] with the function given to {!register}, outside the
    observation of the collector of block accesses. It evaluates no
    predicate. *)
val restore :
  Callstack.t -> kernel_function -> Cvalue.Model.t -> restoration -> unit
