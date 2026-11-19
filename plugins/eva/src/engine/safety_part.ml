(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

type frames = Callstack.call list

type red_target = Alarm of Alarms.t | Prop of Property.t

type write =
  | Emitted_alarm of {
      kinstr : kinstr;
      alarm : Alarms.t;
      status : Property_status.emitted_status;
      emitter : Emitter.t;
      predicate : predicate;
      frames : frames;
    }
  | Emitted_status of {
      property : Property.t;
      status : Property_status.emitted_status;
      emitter : Emitter.t;
      frames : frames;
    }
  | Status_message of {
      status : Property_status.emitted_status;
      loc : Fileloc.t;
      stacktrace : bool;
      text : string;
      frames : frames;
    }
  | Red_context of {
      kinstr : kinstr;
      target : red_target;
      frames : frames;
    }

type t = write list

let empty = []

let frames = function
  | Emitted_alarm { frames } | Emitted_status { frames }
  | Status_message { frames } | Red_context { frames } -> frames

let reroot (callstack : Callstack.t) frames =
  { callstack with stack = frames @ callstack.stack }

(* ----- Comparison, to record each write once ----------------------------- *)

let compare_frames =
  List.compare
    (fun (kf1, s1) (kf2, s2) ->
       let c = Kernel_function.compare kf1 kf2 in
       if c <> 0 then c else Cil_datatype.Stmt.compare s1 s2)

let compare_target t1 t2 =
  match t1, t2 with
  | Alarm a1, Alarm a2 -> Alarms.compare a1 a2
  | Prop p1, Prop p2 -> Property.compare p1 p2
  | Alarm _, Prop _ -> -1
  | Prop _, Alarm _ -> 1

let rank = function
  | Emitted_alarm _ -> 0
  | Emitted_status _ -> 1
  | Status_message _ -> 2
  | Red_context _ -> 3

(* [emitted_status] has constant constructors only. *)
let compare_status (s1 : Property_status.emitted_status) s2 = compare s1 s2

(* The first comparison that does not give 0, in order. *)
let lexicographic comparisons =
  List.fold_left (fun c compare -> if c <> 0 then c else compare ()) 0
    comparisons

let compare_write w1 w2 =
  match w1, w2 with
  | Emitted_alarm a1, Emitted_alarm a2 ->
    lexicographic
      [ (fun () -> Cil_datatype.Kinstr.compare a1.kinstr a2.kinstr);
        (fun () -> Alarms.compare a1.alarm a2.alarm);
        (fun () -> compare_status a1.status a2.status);
        (fun () -> Emitter.compare a1.emitter a2.emitter);
        (fun () -> compare_frames a1.frames a2.frames) ]
  | Emitted_status s1, Emitted_status s2 ->
    lexicographic
      [ (fun () -> Property.compare s1.property s2.property);
        (fun () -> compare_status s1.status s2.status);
        (fun () -> Emitter.compare s1.emitter s2.emitter);
        (fun () -> compare_frames s1.frames s2.frames) ]
  | Status_message m1, Status_message m2 ->
    lexicographic
      [ (fun () -> Fileloc.compare m1.loc m2.loc);
        (fun () -> String.compare m1.text m2.text);
        (fun () -> compare_status m1.status m2.status);
        (fun () -> Bool.compare m1.stacktrace m2.stacktrace);
        (fun () -> compare_frames m1.frames m2.frames) ]
  | Red_context r1, Red_context r2 ->
    lexicographic
      [ (fun () -> Cil_datatype.Kinstr.compare r1.kinstr r2.kinstr);
        (fun () -> compare_target r1.target r2.target);
        (fun () -> compare_frames r1.frames r2.frames) ]
  | _ -> Int.compare (rank w1) (rank w2)

module Writes = Set.Make (struct type t = write let compare = compare_write end)

(* ----- Printing ---------------------------------------------------------- *)

let pretty_status fmt (status : Property_status.emitted_status) =
  Format.pp_print_string fmt
    (match status with
     | True -> "valid"
     | False_if_reachable -> "invalid"
     | False_and_reachable -> "invalid and reachable"
     | Dont_know -> "unknown")

let pretty_kinstr fmt = function
  | Kglobal -> Format.pp_print_string fmt "global"
  | Kstmt stmt ->
    Format.fprintf fmt "%a (stmt %d)"
      Fileloc.pretty (Cil_datatype.Stmt.loc stmt) stmt.sid

let pretty_frames fmt = function
  | [] -> Format.pp_print_string fmt "the body"
  | frames ->
    let pretty_call fmt (kf, stmt) =
      Format.fprintf fmt "%a :: %a (stmt %d)" Kernel_function.pretty kf
        Fileloc.pretty (Cil_datatype.Stmt.loc stmt) stmt.sid
    in
    Pretty_utils.pp_list ~sep:" <- " pretty_call fmt frames

let pretty_write fmt = function
  | Emitted_alarm { kinstr; alarm; status; emitter; frames; predicate = _ } ->
    Format.fprintf fmt "@[<hov 2>alarm %s at %a,@ status %a by %a,@ in %a@]"
      (Alarms.get_name alarm) pretty_kinstr kinstr pretty_status status
      Emitter.pretty emitter pretty_frames frames
  | Emitted_status { property; status; emitter; frames } ->
    Format.fprintf fmt "@[<hov 2>status %a of %a,@ by %a,@ in %a@]"
      pretty_status status Property.short_pretty property
      Emitter.pretty emitter pretty_frames frames
  | Status_message { status; loc; stacktrace; text; frames } ->
    Format.fprintf fmt "@[<hov 2>message %S at %a,@ for a status %a%s,@ in %a@]"
      text Fileloc.pretty loc pretty_status status
      (if stacktrace then ", with the callstack" else "")
      pretty_frames frames
  | Red_context { kinstr; target; frames } ->
    let pretty_target fmt = function
      | Alarm alarm -> Format.fprintf fmt "alarm %s" (Alarms.get_name alarm)
      | Prop property ->
        Format.fprintf fmt "property %a" Property.short_pretty property
    in
    Format.fprintf fmt "@[<hov 2>red context of %a at %a,@ in %a@]"
      pretty_target target pretty_kinstr kinstr pretty_frames frames

let pretty fmt = function
  | [] -> Format.pp_print_string fmt "none"
  | writes ->
    Pretty_utils.pp_list ~pre:"@[<v>" ~sep:"@ " pretty_write fmt writes

(* ----- Recording --------------------------------------------------------- *)

(* The writes of a body called with [base], in the project [project],
   newest first. [changes] is the count of the changes of the current
   project at the start of the recording. [seen] holds the alarms and
   statuses recorded. *)
type recorder = {
  base : Callstack.t;
  project : Project.t;
  changes : int;
  mutable writes : write list;
  mutable seen : Writes.t;
}

let current : recorder option ref = ref None

module Hooks = Hook.Build (struct type nonrec t = Callstack.t * t end)

let unaudited = ref false
let has_unaudited_observers () = !unaudited

let on_result ?(audited = false) f =
  if not audited then unaudited := true;
  Hooks.extend (fun (stack, writes) -> f stack writes)

let capture base analyse =
  let previous = !current in
  let r =
    { base; project = Project.current ();
      changes = Project.current_changes (); writes = []; seen = Writes.empty }
  in
  current := Some r;
  let output =
    Fun.protect analyse ~finally:(fun () -> current := previous)
  in
  let writes = List.rev r.writes in
  Body_access.without_recording (fun () -> Hooks.apply (base, writes));
  output, writes

(* The calls of [callstack] above [base], if [callstack] extends [base]. *)
let relative (base : Callstack.t) (callstack : Callstack.t) =
  let rec split n stack =
    if n = 0 then Some ([], stack)
    else
      match stack with
      | [] -> None
      | call :: rest ->
        Option.map (fun (above, below) -> call :: above, below)
          (split (n - 1) rest)
  in
  let depth = List.length callstack.stack - List.length base.stack in
  if depth < 0 then None
  else
    match split depth callstack.stack with
    | Some (frames, below)
      when Callstack.equal { callstack with stack = below } base ->
      Some frames
    | _ -> None

(* Records the write [make frames]. An alarm or a status equal to one
   already recorded changes no table and runs no hook again: it is not
   recorded. A message is recorded at each emission, since the logger
   decides at each one whether to print it, and a red context at each
   emission, since it runs the hooks of red statuses each time: each one
   takes its place in the sequence. A write made after a change of the
   current project, in another project or back in the first one, refuses
   the recording instead; the writes passed to the observers of
   {!on_result} are thus all made in the project of the recording. The
   checks of the [requires] clauses of a body belong to its call site
   ({!Body_access.at_call_site}), and are not recorded. *)
let record make =
  match !current with
  | Some r
    when Body_access.is_recording ()
      && not (Body_access.checking_call_site ()) ->
    if Project.current_changes () <> r.changes
    || not (Project.is_current r.project)
    then Body_access.refuse Project_switch
    else begin
      let frames =
        match Current_callstack.get () with
        | None -> None
        | Some callstack -> relative r.base callstack
      in
      match frames with
      | None -> Body_access.refuse Side_table
      | Some frames ->
        match make frames with
        | (Red_context _ | Status_message _) as write ->
          r.writes <- write :: r.writes
        | (Emitted_alarm _ | Emitted_status _) as write ->
          if not (Writes.mem write r.seen) then begin
            r.seen <- Writes.add write r.seen;
            r.writes <- write :: r.writes
          end
    end
  | _ -> ()

let record_alarm kinstr alarm status emitter predicate =
  record (fun frames ->
      Emitted_alarm { kinstr; alarm; status; emitter; predicate; frames })

let record_red_context kinstr target =
  record (fun frames -> Red_context { kinstr; target; frames })

let emit_status emitter property status =
  record (fun frames ->
      Emitted_status { property; status; emitter; frames });
  Property_status.emit ~distinct:true emitter ~hyps:[] property status

let status_message status ~loc ~stacktrace text =
  record (fun frames ->
      Status_message { status; loc; stacktrace; text; frames });
  Body_access.replayed_message @@ fun () ->
  match (status : Property_status.emitted_status) with
  | True ->
    Self.result ~mkey:Log_key.progress ~once:true ~loc ~stacktrace "%s" text
  | False_if_reachable | False_and_reachable | Dont_know ->
    Self.warning ~wkey:Log_key.warn_alarm ~once:true ~loc ~stacktrace "%s"
      text
