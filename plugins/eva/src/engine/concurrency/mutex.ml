(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* --- Mutex definition --- *)

module Data = struct
  type t = Concurrency.Name.t option
  let repr = None
  let name = "mutex"
  let array_of_ids = Mt_lib.array_mutexes

  let pretty fmt (name, id) =
    match name with
    | Some name -> Concurrency.Name.pretty fmt name
    | None -> Format.fprintf fmt "#%i" id
end

(* The identity of a mutex is used to choose how to group mutex creations
   during the analysis. This is especially useful if the mutex is created inside
   a - potentially not unrolled - loop. *)
module Identity = struct
  type t =
    | ByName of Concurrency.Name.t
    | ByCreationPoint of Position.Local.t
  [@@deriving eq, ord]

  let repr = ByName (Concurrency.Name.of_string "dummy")

  let hash = function
    | ByName name -> Hashtbl.hash(1, Concurrency.Name.hash name)
    | ByCreationPoint al -> Hashtbl.hash(2, Position.Local.hash al)
end

include Mt_ids.Make (Identity) (Data)

let create creation_point name =
  let identity = match name with
    | Some name -> Identity.ByName name
    | None -> ByCreationPoint creation_point
  in
  create identity name
