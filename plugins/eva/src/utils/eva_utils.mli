(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

(** {2 Others} *)

(** Emitter of alarms and logical statuses evaluated by the analysis. *)
val emitter : Emitter.t

(** Emitter of code annotations stating the properties inferred by an analysis,
    intended for other plug-ins. Used by the {!Export} module. *)
val export_emitter : Emitter.t


(* Statements for which the analysis has degenerated. [true] means that this is
   the statement on which the degeneration occurred, or a statement above in
   the callstack *)
module DegenerationPoints:
  State_builder.Hashtbl with type key = stmt and type data = bool


val create_new_var: ?alignas:int -> string -> typ -> varinfo
(** Create and register a new variable inside Frama-C. The variable
    has its [vlogic] field set, meaning it is not a source variable. The
    freshness of the name must be ensured by the user. *)

val find_return_var: kernel_function -> varinfo option
(** Returns the varinfo returned by the given function.
    Returns None if the function returns void or has no return statement. *)

val postconditions_mention_result: Cil_types.funspec -> bool
(** Does the post-conditions of this specification mention [\result]? *)

val conv_relation: relation -> Abstract_interp.Comp.t

(** Computes the height of an expression, that is the maximum number of nested
    operations in this expression. *)
val height_expr: exp -> int

(** Computes the height of an lvalue. *)
val height_lval: lval -> int

val skip_specifications: kernel_function -> bool
(** Should we skip the specifications of this function, according to
    [-eva-skip-stdlib-specs] *)

(** Creates an unmarshallable copy of the given datatype. Useful to create
    {!State_builder} tables which should not be saved on disk. *)
module Do_Not_Marshal (Input: Datatype.S) : Datatype.S with type t = Input.t
