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

(** [register ~name ~needed ~restore ()] declares a part named [name].
    - [needed ()] tells whether a consumer of the part is enabled in the
      current analysis. While it holds, a hit needs the part. It must not
      change during an analysis.
    - [restore callstack kf pre value] restores [value], the part of the
      entry used by a hit at a call of [kf] with [callstack], whose cvalue
      state at the start of the call is [pre]. It is called at the place
      where the fresh analysis of the body sends its results to the hooks
      of {!Cvalue_callbacks}, after the call hooks with [`Reuse] and the
      check of the preconditions, and before the caller uses the states at
      the end of the call. The collector of block accesses does not observe
      it.

    Parts are registered when their owner is loaded, before any analysis. *)
val register :
  name:string -> needed:(unit -> bool) ->
  restore:(Callstack.t -> kernel_function -> Cvalue.Model.t -> 'a -> unit) ->
  unit -> 'a t

val name : 'a t -> string

(** [provide part callstack value] gives [value] as the part computed by the
    fresh analysis of the body called with [callstack]. It must be called
    during this analysis, after the analysis of the calls made by the body:
    for instance from a hook of {!Cvalue_callbacks} that receives the
    [`Body] results of the call. The value is kept when the innermost body
    being analysed through the cache is called with [callstack] and when the
    current project is the one in which its analysis started. Otherwise it
    is dropped, and the entry produced from this analysis lacks the part. A
    second value given for the same part and the same analysis replaces the
    first. *)
val provide : 'a t -> Callstack.t -> 'a -> unit

(** [register_state_reader ~name reads] declares a consumer that reads the
    states that Eva saves at the statements of the functions, while
    [reads ()] holds in the current analysis. A hit saves no state at the
    statements of the called function, and no part restores them: while a
    declared reader reads, every candidate entry is rejected. A reader that
    is not declared, or that reads later than the analysis without having
    declared it, is not detected. *)
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

(** Whether [parts] has every part whose consumer is enabled. *)
val supplies : parts -> bool

(** Whether a reader declared by {!register_state_reader} reads in the
    current analysis. *)
val reads_statement_states : unit -> bool

(** [restore callstack kf pre parts] restores each part of [parts] whose
    consumer is enabled, in the order of registration, with the function
    given to {!register}, outside the observation of the collector of block
    accesses. Raises [Invalid_argument] if a part whose consumer is enabled
    is missing: the lookup rejects such an entry. *)
val restore : Callstack.t -> kernel_function -> Cvalue.Model.t -> parts -> unit
