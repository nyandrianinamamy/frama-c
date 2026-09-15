(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module type T = sig
  type value
  type origin
  type loc

  type val_report
  type loc_report

  val default_val_report : val_report
  val default_loc : loc
end

module Make (T : T) : sig

  type val_record = (T.value, T.origin) Eval.record_val
  type loc_record = T.loc Eval.record_loc

  type val_entry = val_record * T.val_report
  type loc_entry = loc_record * T.loc_report

  type valuation

  type t = valuation ref

  val create : unit -> t
  val find_val : t -> Eva_ast.exp -> val_entry
  val find_loc : t -> Eva_ast.lval -> loc_entry
  val add_val : t -> Eva_ast.exp -> val_entry -> unit
  val add_loc : t -> Eva_ast.lval -> loc_entry -> unit
  val remove_val : t -> Eva_ast.exp -> unit
  val remove_loc : t -> Eva_ast.lval -> unit

  module Valuation : Eval.Valuation
    with type t = valuation
     and type value = T.value
     and type origin = T.origin
     and type loc = T.loc
end
