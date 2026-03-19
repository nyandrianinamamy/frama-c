(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Lattice_bounds

type offset =
  | NoOffset of Cil_types.typ
  | Index of
      Eva_ast.exp (* lower bound *) *
      Eva_ast.exp (* upper bound *) *
      Cil_types.typ (* type of elements *) *
      offset  (* sub-offset *)
  | Field of Cil_types.fieldinfo * offset

include Datatype.S_with_collections with type t = offset

val of_var_address : Cil_types.varinfo -> t
val of_eva_offset : oracle:(Eva_ast.exp -> Int_val.t) ->
  Cil_types.typ -> Eva_ast.offset -> t or_top
val of_ival : base_typ:Cil_types.typ -> typ:Cil_types.typ -> Ival.t -> t or_top
val of_term_offset : Cil_types.typ -> Cil_types.term_offset -> t or_top

val is_singleton : oracle:(Eva_ast.exp -> Int_val.t) -> t -> bool
val references : t -> Cil_datatype.Varinfo.Set.t (* variables referenced in the offset *)

val append : t -> t -> t (* Does not check that the appended offset fits *)
(* val join : t -> t -> t or_top *)
val add_index : oracle:(Eva_ast.exp -> Int_val.t) -> t -> Eva_ast.exp -> t or_top
