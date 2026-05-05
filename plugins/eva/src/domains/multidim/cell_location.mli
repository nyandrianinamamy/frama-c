(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval

include Datatype.S_with_collections
type offset = Abstract_offset.t or_top
type oracle = Cell_oracle.oracle

val empty : t
val bases : t -> Base.t list
val references : t -> Cil_types.varinfo list

val singleton : Base.t -> Abstract_offset.t -> t
val is_singleton : oracle:oracle -> t -> bool
val to_singleton_var : t -> Cil_types.varinfo option

val of_var : Cil_types.varinfo -> t
val of_lval : oracle:oracle -> Eva_ast.lval -> t or_top
val of_precise_loc : Precise_locs.precise_location -> t

val of_term :
  'a Abstract_domain.logic_environment -> Cil_types.term ->
  (t * Cil_types.logic_type) or_top

val fold : (Base.t -> Abstract_offset.t or_top -> 'a -> 'a) -> t -> 'a -> 'a
