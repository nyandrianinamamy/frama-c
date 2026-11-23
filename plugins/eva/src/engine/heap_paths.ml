(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type sweeps = { every: Base.Hptset.t; some: Base.Hptset.t }

let no_sweep = { every = Base.Hptset.empty; some = Base.Hptset.empty }

let sweep ~exact block =
  let blocks = Base.Hptset.singleton block in
  if exact
  then { every = blocks; some = Base.Hptset.empty }
  else { every = Base.Hptset.empty; some = blocks }

let weaken sweeps =
  if Base.Hptset.is_empty sweeps.every then sweeps
  else
    { every = Base.Hptset.empty;
      some = Base.Hptset.union sweeps.every sweeps.some }

let equal_sweeps a b =
  Base.Hptset.equal a.every b.every && Base.Hptset.equal a.some b.some

(* Per block, the classes form a flat lattice: not swept and swept on every
   path are below swept on some path only. *)
let merge a b =
  if equal_sweeps a b then a
  else
    let every = Base.Hptset.inter a.every b.every in
    let all =
      Base.Hptset.(union (union a.every b.every) (union a.some b.some))
    in
    { every; some = Base.Hptset.diff all every }

let sequence first next =
  if equal_sweeps next no_sweep then first
  else
    let every = Base.Hptset.union first.every next.every in
    let some = Base.Hptset.union first.some next.some in
    { every; some = Base.Hptset.diff some every }

let promote f sweeps =
  let promoted = Base.Hptset.filter f sweeps.some in
  if Base.Hptset.is_empty promoted then sweeps
  else
    { every = Base.Hptset.union sweeps.every promoted;
      some = Base.Hptset.diff sweeps.some promoted }

type t = { covered: Base.Hptset.t; sweeps: sweeps }

let empty = { covered = Base.Hptset.empty; sweeps = no_sweep }

let equal a b =
  Base.Hptset.equal a.covered b.covered && equal_sweeps a.sweeps b.sweeps

let join a b =
  { covered = Base.Hptset.union a.covered b.covered;
    sweeps = merge a.sweeps b.sweeps }

let after value next =
  { covered = Base.Hptset.union value.covered next.covered;
    sweeps = sequence value.sweeps next.sweeps }

(* The classes of a block only rise in the lattice of [merge] along the
   iterations, and the covered blocks only grow: the widening is the join,
   and the iteration ends. *)
let compute automaton ~fired ~edge ~vertex =
  let join_values = join in
  let module Analysis =
    Eva_automata.ForwardAnalysis
      (struct
        type nonrec t = t
        let join _ = join_values
        let widen previous next =
          let joined = join_values previous next in
          if equal joined previous
          then Eva_automata.Fixpoint
          else Eva_automata.Widening joined
        let transfer (_, e, v) value =
          if fired e then Some (after (after value (edge e)) (vertex v))
          else None
      end)
  in
  let initial = after empty (vertex automaton.Eva_automata.entry_point) in
  Analysis.fixpoint automaton initial
