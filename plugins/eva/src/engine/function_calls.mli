(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

(** True if the results should be saved for the given function. *)
val save_results: fundec -> bool

(** What is used for the analysis of a given function:
    - a Cvalue builtin (and other domains use the specification)
    - the function specification
    - the function body. The boolean indicates whether the resulting states
      must be recorded at each statement of this function. *)
type analysis_target =
  [ `Builtin of string * Builtins.builtin * funspec
  | `Spec of Cil_types.funspec
  | `Body of Cil_types.fundec * bool ]

(** Returns the analysis target of a given function at a given callsite
    according to Eva parameters. *)
val analysis_target:
  ?recursion_depth:int -> kernel_function -> kinstr -> analysis_target

(** Returns true if the Eva analysis use the specification of the given
    function instead of its body to interpret its calls. *)
val use_spec_instead_of_definition:
  ?recursion_depth:int -> kernel_function -> bool

(** Registers the analysis of a call with a given target for functions below. *)
val register_analysis_target: ('l, 'v) Eval.call -> analysis_target -> unit


(** {2 Call relations}

    The readers below answer from the hit log when it describes the current
    results; otherwise they read the legacy table of call relations, which
    {!Legacy_read_guard} reports. *)

(** Returns true if the function has been analyzed. *)
val is_called: kernel_function -> bool

(** Returns the list of inferred callers of the given function. *)
val callers : Cil_types.kernel_function -> Cil_types.kernel_function list

(** Returns the list of inferred callers, and for each of them, the list
    of callsites (the call statements) inside. *)
val callsites: kernel_function -> (kernel_function * stmt list) list

(** Returns the number of callsites that have been analyzed. *)
val nb_callsites: unit -> int

(** For each called function, its callers and the call statements in each
    caller. The entry point is bound to no caller. *)
type relations =
  Cil_datatype.Stmt.Set.t Kernel_function.Map.t Kernel_function.Map.t

(** Sets the call relations of the hit log: [None] when they do not
    describe the current results. *)
val set_recorded_relations: (unit -> relations option) -> unit

(** Whether a call to the function is registered in the legacy table. Part
    of the legacy result store; does not report to {!Legacy_read_guard}:
    its readers report their own read. *)
val registered: kernel_function -> bool


type results = Complete | Partial | NoResults
type analysis_status =
    Unreachable | SpecUsed | Builtin of string | Analyzed of results

(** Returns the current analysis status of a given function. *)
val analysis_status: kernel_function -> analysis_status

(** The functions below are used by Eva_results.ml to save, merge and load
    the results of multiple Eva analyses.  *)

type t
val get_results: unit -> t
val set_results: t -> unit

(** Merges the analysis statuses of two calls to the same function, as the
    status table does. *)
val merge_status: analysis_status -> analysis_status -> analysis_status

(** [make_results statuses relations]: the analysis status of each function
    of [statuses], and its callers in [relations], as {!get_results}
    exports them. *)
val make_results: analysis_status Kernel_function.Map.t -> relations -> t
