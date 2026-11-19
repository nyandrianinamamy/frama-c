(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Trace = Datatype.Make (struct
    include Datatype.Undefined
    type t = Body_access.call_trace
    let name = "Eva.Cache_call_trace.Trace"
    let reprs = [Body_access.{ functions = []; recursive = false }]
    let mem_project = Datatype.never_any_project
  end)

module Table =
  State_builder.Int_hashtbl
    (Eva_utils.Do_Not_Marshal (Trace))
    (struct
      let name = "Eva.Cache_call_trace.Table"
      let dependencies = [ Self.state ]
      let size = 17
    end)

let remember id (observation : Body_access.Result.t) =
  let trace = Body_access.{
      functions = observation.used_functions;
      recursive = List.mem Result.Recursion observation.refusals;
    }
  in
  Table.replace id trace

let find = Table.find_opt
let clear = Table.clear
