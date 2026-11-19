(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Pdg_types

type t = PdgTypes.Pdg.t

(**************************************************************************)

let compute = Build.compute_pdg

module Tbl =
  Kernel_function.Make_Table
    (PdgTypes.Pdg)
    (struct
      let name = "Pdg.State"
      let dependencies = [] (* postponed because From.self may not exist yet *)
      let size = 17
    end)

let self = Tbl.self

(* A graph is built from the states that Eva saves at the statements of the
   function. A hit of the cache of Eva saves none at the statements of the
   called function, where the results give the top state: the graph would
   not be the one of an analysis of the body.
   The analysis runs first, since its hits make these states incomplete; the
   test then comes before the table, which may hold a graph built before a
   hit of the current analysis. *)
let check_statement_results () =
  if not (Eva.Analysis.is_computed ()) then Eva.Analysis.compute ();
  if not (Eva.Results.statement_results_complete ()) then
    Pdg_parameters.abort
      "cannot compute the dependence graph of a function: in the current \
       analysis of Eva, a hit of the cache answered a call without analysing \
       the body of the called function, and saved no state at its \
       statements"

let get kf =
  check_statement_results ();
  Tbl.memo compute kf

(**************************************************************************)

let pretty ?(bw=false) fmt pdg =
  let kf = PdgTypes.Pdg.get_kf pdg in
  Format.fprintf fmt "@[RESULT for %s:@]@\n@[ %a@]"
    (Kernel_function.get_name kf) (PdgTypes.Pdg.pretty_bw ~bw) pdg

let pretty_node short =
  if short then PdgTypes.Node.pretty
  else PdgTypes.Node.pretty_node

let print_dot pdg filename =
  PdgTypes.Pdg.build_dot filename pdg;
  Pdg_parameters.feedback "dot file generated in %s" filename

let pretty_key = PdgIndex.Key.pretty

(**************************************************************************)
