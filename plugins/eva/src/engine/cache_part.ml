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
  if List.exists (fun p -> p.packed_name = name) !registered then
    Format.kasprintf invalid_arg
      "Cache_part.register: a part named %s is already registered" name;
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

(* A value of a part, with the blocks read to compute it. *)
type value = {
  value : exn;
  reads : Base.SetLattice.t;
}

(* The parts of an entry: identifier of the part and its value. *)
type parts = (int * value) list

let empty = []

let find part parts =
  match List.assoc_opt part.id parts with
  | None -> None
  | Some { value } -> part.project value

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
let provide part callstack ~reads value =
  match !frames with
  | frame :: _
    when Callstack.equal frame.callstack callstack
      && Project.is_current frame.project ->
    let others = List.remove_assoc part.id frame.parts in
    frame.parts <- (part.id, { value = part.inject value; reads }) :: others
  | _ -> ()

(* ----- Coverage by the key ----------------------------------------------- *)

let uncovered_read = "uncovered-read"

(* A local variable of the body, formals excluded, does not exist when the
   call starts: its value at each statement is computed by the body. *)
let own_local kf = function
  | Base.Var (vi, _) ->
    not vi.vglob && not (Kernel_function.is_formal vi kf)
    && Kernel_function.is_local vi kf
  | _ -> false

let covered kf ~key { reads } =
  match reads with
  | Base.SetLattice.Top -> false
  | Base.SetLattice.Set bases ->
    Base.Hptset.for_all (fun b -> Base.Hptset.mem b key || own_local kf b)
      bases

let cover kf ~key parts =
  List.filter (fun (_, value) -> covered kf ~key value) parts

(* ----- Consumers --------------------------------------------------------- *)

let supplies parts =
  List.for_all
    (fun p -> not (p.packed_needed ()) || List.mem_assoc p.packed_id parts)
    !registered

let state_readers : (string * (unit -> bool)) list ref = ref []

let register_state_reader ~name reads =
  state_readers := !state_readers @ [ name, reads ]

(* The plug-ins that request the results by function of From or Inout,
   each of which depends on From or Inout. They are known by name: Eva does
   not depend on them. The rule is by dependency: a plug-in that loads one of
   them is covered by it. Impact, Scope, Security-slicing, Slicing and
   Sparecode load Pdg. *)
let requesting_plugins = [ "pdg"; "reduc"; "studia" ]

let reads_statement_states () =
  List.exists Plugin.is_present requesting_plugins
  || List.exists (fun (_, reads) -> reads ()) !state_readers

let restore callstack kf pre parts =
  let restore_one p =
    if p.packed_needed () then
      match List.assoc_opt p.packed_id parts with
      | Some { value } -> p.packed_restore callstack kf pre value
      | None ->
        Format.kasprintf invalid_arg
          "Cache_part.restore: the part %s is missing" p.packed_name
  in
  Body_access.without_recording (fun () -> List.iter restore_one !registered)
