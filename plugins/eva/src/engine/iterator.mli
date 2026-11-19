(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

(** Provided [stmt] is an 'if' construct, [fst (condition_truth_value stmt)]
    (resp. snd) is true if and only if the condition of the 'if' has been
    evaluated to true (resp. false) at least once during the analysis. *)
val condition_truth_value: stmt -> bool * bool

(** [add_condition stmt outcome] records that the condition of [stmt] has
    been evaluated to [outcome]. The record is a join: a branch once taken
    stays taken. It is also recorded in the Reach part of the body being
    analysed, if any ({!Reach_part}). *)
val add_condition: stmt -> bool -> unit


(** Subset of [Engine_sig.S] required by this functor. *)
module type Engine_Subset = sig
  (* Abstractions with the evaluator. *)
  include Engine_abstractions_sig.S
  (* Initialization of local variables. *)
  module Initialization : Engine_sig.Initialization with type state = Dom.t
  (* Transfer functions on statements. *)
  module Transfer_stmt : Engine_sig.Transfer_stmt with type state = Dom.t
  (* Transfer functions on logic annotations. *)
  module Transfer_logic : Engine_sig.Transfer_logic with type state = Dom.t
  (* Interpretation of statement assigns. *)
  module Transfer_specification : sig
    val treat_statement_assigns: pos:Position.t -> assigns -> Dom.t -> Dom.t
  end
end

module Make (Engine: Engine_Subset) :
  Engine_sig.Iterator with type state = Engine.Dom.t
