(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

(** Access information shared by the collector and cache entries. *)

type call_mode = [ `Body | `Spec | `Builtin ]

type recorded =
  | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

type observation = {
  designated : Base.SetLattice.t;
  recorded : recorded list;
  functions : (kernel_function * call_mode) list;
}

(** The blocks that a statement analysed from one input may access. The
    footprint is R ∪ W, and W_sure ⊆ W_exit ⊆ W. A block written only on
    paths that reach no exit is in W and not in W_exit: at an exit it holds
    the value it had in the input.
    - [read], R: the blocks it may read;
    - [written], W: the blocks it may write;
    - [written_exit], W_exit: the blocks it may write on a path that reaches
      an exit of the statement;
    - [written_sure], W_sure: the blocks it certainly and fully overwrites on
      every path that reaches an exit. *)
type footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

(** An opaque reference to an entry. Its domain-specific implementation
    supplies the constructor and can recover the entry from the reference. *)
type reference = ..

type child = stmt * reference
