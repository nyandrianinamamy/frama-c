(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

module Sign_Value = struct
  include Sign_value

  (* In this domain, we only track integer variables. *)
  let track_variable vi = Ast_types.C.is_integral vi.vtype

  (* The base lattice is finite, we can use join to perform widening *)
  let widen ~size:_ ~hint:_ = join

  let builtins = []
end

module Name = struct let name = "sign" end
module Simple = Simple_memory.Make_Domain (Name) (Sign_Value)
module Cell = Cell_memory.Make (Name) (Sign_Value)

let choose () : (module Abstract_domain.Leaf) =
  match Parameters.SignMemoryModel.get () with
  | `Simple -> (module Simple)
  | `Cell -> (module Cell)

let registered =
  let name = "sign"
  and descr = "Infers the sign of program variables." in
  Abstractions.Domain.dynamic_register ~name ~descr ~priority:4 choose
