(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

type call_mode = [ `Body | `Spec | `Builtin ]

type recorded =
  | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

type observation = {
  designated : Base.SetLattice.t;
  recorded : recorded list;
  functions : (kernel_function * call_mode) list;
}

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
