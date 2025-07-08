(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Basic_locations

val is_no_effect_frama_c_builtin : Eva_ast.lhost -> bool

type written_locs = {
  last_writes : VMemLocMap.t;
  ptr_targets : MlsMemLocMap.t;
}

module WrittenLocs (_ : sig val include_guards : bool end) :
sig
  include Eva_automata.Domain with type t = written_locs

  val initial : Cil_types.varinfo list -> t
end
