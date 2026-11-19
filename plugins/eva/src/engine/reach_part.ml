(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

type frames = Callstack.call list

type write =
  | Reached of { point : Domain_store.control_point; frames : frames }
  | Guard of { stmt : stmt; outcome : bool }
  | Zones of {
      stmt : stmt;
      frames : frames;
      read : Memory_zone.t;
      write : Memory_zone.t;
    }
  | Caller of { frames : frames }

type t = write list

let empty = []

let reroot = Safety_part.reroot

(* ----- Printing ---------------------------------------------------------- *)

let pretty_stmt fmt stmt =
  Format.fprintf fmt "%a (stmt %d)"
    Fileloc.pretty (Cil_datatype.Stmt.loc stmt) stmt.sid

let pretty_point fmt (point : Domain_store.control_point) =
  match point with
  | Initial -> Format.pp_print_string fmt "the initial state"
  | Start kf -> Format.fprintf fmt "start of %a" Kernel_function.pretty kf
  | Before stmt -> Format.fprintf fmt "before %a" pretty_stmt stmt
  | After stmt -> Format.fprintf fmt "after %a" pretty_stmt stmt

let pretty_write fmt = function
  | Reached { point; frames } ->
    Format.fprintf fmt "@[<hov 2>reached %a,@ in %a@]"
      pretty_point point Safety_part.pretty_frames frames
  | Guard { stmt; outcome } ->
    Format.fprintf fmt "@[<hov 2>guard %a: %s@]"
      pretty_stmt stmt (if outcome then "then" else "else")
  | Zones { stmt; frames; read; write } ->
    Format.fprintf fmt "@[<hov 2>zones at %a,@ read %a,@ write %a,@ in %a@]"
      pretty_stmt stmt Memory_zone.pretty read Memory_zone.pretty write
      Safety_part.pretty_frames frames
  | Caller { frames } ->
    Format.fprintf fmt "@[<hov 2>caller site of %a@]"
      Safety_part.pretty_frames frames

let pretty fmt = function
  | [] -> Format.pp_print_string fmt "none"
  | writes ->
    Pretty_utils.pp_list ~pre:"@[<v>" ~sep:"@ " pretty_write fmt writes

(* ----- Recording --------------------------------------------------------- *)

(* The identity of a write, to keep each write once. It holds integers only,
   for the polymorphic hash table. *)
type key =
  | Point_key of int * int * (int * int) list
  | Guard_key of int * bool
  | Zones_key of int * (int * int) list
  | Caller_key of (int * int) list

let frames_key frames =
  List.map (fun (kf, stmt) -> Kernel_function.get_id kf, stmt.sid) frames

let point_key (point : Domain_store.control_point) frames =
  let tag, id =
    match point with
    | Initial -> 0, 0
    | Start kf -> 1, Kernel_function.get_id kf
    | Before stmt -> 2, stmt.sid
    | After stmt -> 3, stmt.sid
  in
  Point_key (tag, id, frames_key frames)

(* The writes of a body called with [base], in the project [project].
   [changes] is the count of the changes of the current project at the
   start of the recording. [order] holds the keys of the writes, newest
   first, each at its first emission. *)
type recorder = {
  base : Callstack.t;
  project : Project.t;
  changes : int;
  mutable order : key list;
  writes : (key, write) Hashtbl.t;
}

let current : recorder option ref = ref None

module Hooks = Hook.Build (struct type nonrec t = Callstack.t * t end)

let on_result f = Hooks.extend (fun (stack, writes) -> f stack writes)

let capture base analyse =
  let previous = !current in
  let r =
    { base; project = Project.current ();
      changes = Project.current_changes (); order = [];
      writes = Hashtbl.create 17 }
  in
  current := Some r;
  let output =
    Fun.protect analyse ~finally:(fun () -> current := previous)
  in
  let writes = List.rev_map (Hashtbl.find r.writes) r.order in
  Body_access.without_recording (fun () -> Hooks.apply (base, writes));
  output, writes

(* Runs [f] on the recorder of the body, under the conditions of
   {!Safety_part.record}: while the collector observes the body itself,
   outside the checks of its [requires] clauses, and in the project of the
   recording. *)
let with_recorder f =
  match !current with
  | Some r
    when Body_access.is_recording ()
      && not (Body_access.checking_call_site ()) ->
    if Project.current_changes () <> r.changes
    || not (Project.is_current r.project)
    then Body_access.refuse Project_switch
    else f r
  | _ -> ()

(* Adds [write] under [key], or replaces the write already there by
   [join previous]. *)
let add r key ~join write =
  match Hashtbl.find_opt r.writes key with
  | None ->
    Hashtbl.replace r.writes key write;
    r.order <- key :: r.order
  | Some previous -> Hashtbl.replace r.writes key (join previous)

let keep previous = previous

(* Records [make frames] with the frames of [callstack] above the body. *)
let record_in callstack make =
  with_recorder @@ fun r ->
  match Safety_part.relative r.base callstack with
  | None -> Body_access.refuse Side_table
  | Some frames -> make r frames

let record_state callstack (point : Domain_store.control_point) =
  match point with
  | Initial -> ()
  | Start _ | Before _ | After _ ->
    record_in callstack @@ fun r frames ->
    add r (point_key point frames) ~join:keep (Reached { point; frames })

let record_guard stmt outcome =
  with_recorder @@ fun r ->
  add r (Guard_key (stmt.sid, outcome)) ~join:keep (Guard { stmt; outcome })

let record_zones (position : Position.t) ~read ~write =
  match position with
  | Local (stmt, callstack) ->
    record_in callstack @@ fun r frames ->
    let join = function
      | Zones z ->
        Zones { z with read = Memory_zone.join z.read read;
                       write = Memory_zone.join z.write write }
      | previous -> previous
    in
    add r (Zones_key (stmt.sid, frames_key frames)) ~join
      (Zones { stmt; frames; read; write })
  | RootCall _ | GlobalInit _ ->
    with_recorder (fun _ -> Body_access.refuse Side_table)

let record_caller callstack =
  record_in callstack @@ fun r frames ->
  match frames with
  | [] -> ()
  | _ :: _ -> add r (Caller_key (frames_key frames)) ~join:keep
                (Caller { frames })
