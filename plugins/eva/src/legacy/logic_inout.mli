(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Functions used by the Inout and From plugins to interpret predicate
    and assigns clauses. This API may change according to these plugins
    development. *)

(** [predicate_deps ~pre ~here p] computes the logic dependencies needed
    to evaluate the predicate [p] in cvalue state [here], in a function
    whose pre-state is [pre].
    Returns None on either an evaluation error or on unsupported construct. *)
val predicate_deps:
  pre:Cvalue.Model.t -> here:Cvalue.Model.t ->
  Cil_types.predicate -> Memory_zone.t option

(** {2 Memory read by the predicates that Eva interprets}

    The functions below over-approximate the memory that Eva reads to
    evaluate the predicates of a function, and to reduce its states by them,
    when it analyzes a call to this function from the given states. The
    states are cvalue states; they must include the states that Eva meets.
    The predicates that Eva ignores are left out. The clauses of kind check
    are included: Eva does not reduce by them, but emits their status. The
    labels not bound by Eva are bound to the top state, as Eva does. The
    result is [Memory_zone.top] if the dependencies of a part of a predicate
    cannot be computed. *)

(** [annotation_deps ~pre ~here p] is the memory read by Eva to interpret
    the assertion or loop invariant [p] in the state [here], in a function
    whose pre-state is [pre]. *)
val annotation_deps:
  pre:Cvalue.Model.t -> here:Cvalue.Model.t ->
  Cil_types.predicate -> Memory_zone.t

(** [precondition_deps kf ~pre] is the memory read by Eva to interpret the
    preconditions of [kf] in its pre-state [pre], before analyzing its body:
    the assumes clauses of all behaviors, which decide their activity, and
    the requires clauses of the behaviors that may be active. *)
val precondition_deps:
  Cil_types.kernel_function -> pre:Cvalue.Model.t -> Memory_zone.t

(** [postcondition_deps kf ~pre ~here ~return] is the memory read by Eva to
    interpret the normal postconditions of [kf] at its return statement,
    for the behaviors that may be active. [pre] is its pre-state, [here]
    the state before the return statement, and [return] the value returned,
    if any. The variable that stands for [\result] is left out. *)
val postcondition_deps:
  Cil_types.kernel_function -> pre:Cvalue.Model.t -> here:Cvalue.Model.t ->
  return:Cvalue.V.t option -> Memory_zone.t

(** [specification_deps kf ~pre] is the memory read by Eva to interpret the
    preconditions and normal postconditions of [kf] when it analyzes a call
    to [kf] through its specification, from the state [pre] at the call.
    The postconditions are evaluated in an over-approximation of the state
    after the assigns clauses. The variable that stands for [\result] is
    left out. *)
val specification_deps:
  Cil_types.kernel_function -> pre:Cvalue.Model.t -> Memory_zone.t

(** Returns the list of behaviors of the given function that are active for
    the given initial state. *)
val valid_behaviors:
  Cil_types.kernel_function -> Cvalue.Model.t -> Cil_types.behavior list

(** Evaluation of the memory zone read by the \from part of an assigns clause,
    in the given cvalue state.  *)
val assigns_inputs_to_zone:
  Cvalue.Model.t -> Cil_types.assigns -> Memory_zone.t

(** Evaluation of the memory zone written by an assigns clauses, in the given
    cvalue state. *)
val assigns_outputs_to_zone:
  result: Cil_types.varinfo option ->
  Cvalue.Model.t -> Cil_types.assigns -> Memory_zone.t

(** Zones of an lvalue term of an assigns clause. *)
type tlval_zones = {
  under: Memory_zone.t; (** Under-approximation of the memory zone. *)
  over: Memory_zone.t;  (** Over-approximation of the memory zone. *)
  deps: Memory_zone.t;  (** Dependencies needed to evaluate the address. *)
}

(** Context of an evaluation: in a statement annotation or an assigns clause. *)
type annotation = Code_annot | Assigns

(** Evaluation of the memory zones and dependencies of an lvalue term,
    in the given cvalue state for a read or write access. *)
val tlval_to_zones:
  annotation -> Cvalue.Model.t -> Locations.access ->
  Cil_types.term -> tlval_zones option

(** Evaluate the assigns clauses of the given function in its given pre-state,
    and compare them with the dependencies computed by the from plugin.
    Emits warnings if needed, and sets statuses to the assigns clauses. *)
val verify_assigns:
  Cil_types.kernel_function -> pre:Cvalue.Model.t -> Assigns.t -> unit


(** [accept_base ~formals ~locals kf b] returns [true] if and only if [b] is:
    - a global except if it represents a string literal
    - a formal or local of one of the callers of [kf]
    - a formal or local of [kf] and the corresponding argument is [true]. *)
val accept_base:
  formals:bool -> locals:bool -> Kernel_function.t -> Base.t -> bool
