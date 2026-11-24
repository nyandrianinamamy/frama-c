(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Interface of {!Cvalue_callbacks} exported in Eva.ml. *)
module type API = sig

  type state = Cvalue.Model.t

  (** Registers a function to be applied at the start of an analysis. *)
  val register_at_start_hook: (unit -> unit) -> unit

  (** If not None:
      - the assigns of the function, i.e. the dependencies of the result
        and the dependencies of each zone written to;
      - and its sure outputs, i.e. an under-approximation of written zones. *)
  type call_assigns = (Assigns.t * Memory_zone.t) option

  type analysis_kind =
    [ `Builtin (** A cvalue builtin is used to interpret the function. *)
    | `Spec  (** The specification is used to interpret the function. *)
    | `Body  (** The function body is analyzed. This is the standard case. *)
    | `Reuse (** The results of a previous analysis of the function are reused. *)
    ]

  (** Signature of a hook to be called before the analysis of each function call.
      Arguments are the callstack of the call, the function called, the initial
      cvalue state, and the kind of analysis performed by Eva for this call. *)
  type call_hook =
    Callstack.t -> Cil_types.kernel_function -> state -> analysis_kind -> unit

  (** Registers a function to be applied at the start of the analysis of each
      function call. *)
  val register_call_hook: call_hook -> unit


  type state_by_stmt = (state Cil_datatype.Stmt.Hashtbl.t) Lazy.t
  type results = { before_stmts: state_by_stmt; after_stmts: state_by_stmt }

  (** The cells that the reuse of a call that frees changes by its sweeps,
      outside the inputs and outputs of the previous call it reuses: on some
      path, and on every path that returns. A call analysed by its body
      reports them as written, as [free] does. *)
  type swept = { written: Memory_zone.t; sure: Memory_zone.t }

  (** Results of a function call. *)
  type call_results =
    [ `Builtin of state list * call_assigns
    (** List of cvalue states at the end of the builtin. *)
    | `Spec of state list
    (** List of cvalue states at the end of the call. *)
    | `Body of results * int
    (** Cvalue states before and after each statement of the given function,
        plus a unique integer id for the call. *)
    | `Reuse of int
    (** The results are the same as a previous call with the given integer id,
        previously recorded with the [`Body] constructor. *)
    | `Renamed_reuse of int * Base.substitution
    (** The results are the same as a previous call with the given integer
        id, previously recorded with the [`Body] constructor, with its
        allocated blocks replaced through the substitution, which is not
        empty. Only with option [-eva-hit-log]. *)
    | `Swept_reuse of int * Base.substitution * swept
      (** The same, for the reuse of a call that frees, whose sweeps also
          change cells that the previous call neither read nor wrote. The
          substitution is empty if the blocks are not replaced. Only with
          option [-eva-hit-log]. *)
    ]

  (** Signature of a hook to be called after the analysis of each function call.
      Arguments are the callstack of the call, the function called, the initial
      cvalue state at the start of the call, and the results from its analysis. *)
  type call_results_hook =
    Callstack.t -> Cil_types.kernel_function -> state -> call_results -> unit

  (** Registers a function to be applied at the end of the analysis of each
      function call. *)
  val register_call_results_hook: call_results_hook -> unit

end
