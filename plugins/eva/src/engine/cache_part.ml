(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

(* The values of all parts are kept as exceptions: each part has its own
   constructor, which gives back the type of its values. *)
type 'a t = {
  id : int;
  name : string;
  inject : 'a -> exn;
  project : exn -> 'a option;
}

(* A registered part, with the type of its values hidden. *)
type packed = {
  packed_id : int;
  packed_name : string;
  packed_needed : unit -> bool;
  packed_restore :
    Callstack.t -> kernel_function -> Cvalue.Model.t -> exn -> unit;
}

(* The registered parts, in the order of registration. *)
let registered : packed list ref = ref []

let register (type a) ~name ~needed ~restore () : a t =
  let module M = struct exception Value of a end in
  let inject v = M.Value v in
  let project = function M.Value v -> Some v | _ -> None in
  let id = List.length !registered in
  let part = { id; name; inject; project } in
  let packed_restore callstack kf pre value =
    match project value with
    | Some v -> restore callstack kf pre v
    | None -> assert false
  in
  let packed =
    { packed_id = id; packed_name = name; packed_needed = needed;
      packed_restore }
  in
  registered := !registered @ [ packed ];
  part

let name part = part.name

(* The parts of an entry: identifier of the part and its value. *)
type parts = (int * exn) list

let empty = []

let find part parts =
  match List.assoc_opt part.id parts with
  | None -> None
  | Some value -> part.project value

let names parts =
  List.filter_map
    (fun p ->
       if List.mem_assoc p.packed_id parts then Some p.packed_name else None)
    !registered

(* ----- Parts given during the analysis of a body ------------------------- *)

type frame = {
  callstack : Callstack.t;
  project : Project.t;
  mutable parts : parts;
}

(* The bodies being analysed through the cache, innermost first. *)
let frames : frame list ref = ref []

let capture callstack analyse =
  let frame = { callstack; project = Project.current (); parts = [] } in
  frames := frame :: !frames;
  let finally () = frames := List.filter (fun f -> f != frame) !frames in
  let result = Fun.protect ~finally analyse in
  result, frame.parts

(* A value given while another project is current was computed in the tables
   of that project: it is dropped, as a value given for a body that is not
   the innermost one. *)
let provide part callstack value =
  match !frames with
  | frame :: _
    when Callstack.equal frame.callstack callstack
      && Project.is_current frame.project ->
    let others = List.remove_assoc part.id frame.parts in
    frame.parts <- (part.id, part.inject value) :: others
  | _ -> ()

(* ----- Consumers --------------------------------------------------------- *)

let supplies parts =
  List.for_all
    (fun p -> not (p.packed_needed ()) || List.mem_assoc p.packed_id parts)
    !registered

let state_readers : (string * (unit -> bool)) list ref = ref []

let register_state_reader ~name reads =
  state_readers := !state_readers @ [ name, reads ]

let reads_statement_states () =
  List.exists (fun (_, reads) -> reads ()) !state_readers

let restore callstack kf pre parts =
  let restore_one p =
    if p.packed_needed () then
      match List.assoc_opt p.packed_id parts with
      | Some value -> p.packed_restore callstack kf pre value
      | None ->
        Format.kasprintf invalid_arg
          "Cache_part.restore: the part %s is missing" p.packed_name
  in
  Body_access.without_recording (fun () -> List.iter restore_one !registered)
