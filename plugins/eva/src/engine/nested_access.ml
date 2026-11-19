(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Blocks = Base.Hptset
module Bases = Base.SetLattice
module Zone = Memory_zone

let private_blocks kf return =
  let add blocks vi = Blocks.add (Base.of_varinfo vi) blocks in
  let initial =
    Option.fold ~none:Blocks.empty ~some:(add Blocks.empty) return
  in
  List.fold_left add initial
    (Kernel_function.get_formals kf @ Kernel_function.get_locals kf)

let remove blocks = function
  | Bases.Top -> Bases.top
  | Bases.Set bases -> Bases.inject (Blocks.diff bases blocks)

let full_range base =
  match Base.validity base with
  | Base.Known (lo, hi) -> Some (Int_Intervals.inject_bounds lo hi)
  | _ -> None

let sure_zone blocks =
  let add b zone =
    match full_range b with
    | None -> zone
    | Some bits -> Zone.link zone (Zone.inject b bits)
  in
  Blocks.fold add blocks Zone.bottom

let fully_written zone =
  let add b bits blocks =
    match full_range b with
    | Some range when Int_Intervals.is_included range bits ->
      Blocks.add b blocks
    | _ -> blocks
  in
  Zone.fold_i add zone Blocks.empty
