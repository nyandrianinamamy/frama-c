(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* The run identifier prevents a test-supplied entry from comparing
   generations that came from different analyses. *)
type t = int * int

module Stamp = Datatype.Pair (Datatype.Int) (Datatype.Int)

module Current = State_builder.Ref (Stamp) (struct
    let name = "Eva.Widen_generation.Current"
    let dependencies = [ Self.state ]
    let default () = 0, 0
  end)

let last_run = ref 0

let start_run () =
  incr last_run;
  Current.set (!last_run, 0)

let advance () =
  let run, step = Current.get () in
  Current.set (run, step + 1)

let current = Current.get
let number = snd
let equal = Stamp.equal
