(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval

type oracle = exp -> Cvalue.V.t
type getter = oracle:(exp -> Cvalue.V.t) -> lval -> Cvalue.V.t or_bottom

val convert_oracle : oracle -> exp -> Int_val.t

val default_oracle : getter -> oracle
