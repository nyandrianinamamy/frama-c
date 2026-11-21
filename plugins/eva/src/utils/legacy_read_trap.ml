(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type access =
  | Joined
  | Callstack of Callstack.t
  | Callstacks

type read = {
  store: string;
  access: access;
  point: string;
}

type request = {
  number: int;
  description: string;
  pass: string option;
  reads: read list;
}

type stray = {
  in_pass: string option;
  read: read;
}

(* The request being served: reported with its reads so far, latest first,
   or started during an analysis. *)
type served =
  | Reported of read list ref
  | Ignored

let on = ref false
(* The session of the report: incremented by each [start]. A request that
   started in an earlier session is left out of the report. *)
let session = ref 0
(* Projects whose iteration is running, innermost first. *)
let analyses : Project.t list ref = ref []
(* The passes that Eva runs after the iteration, being run, with their
   project, innermost first. *)
let passes : (Project.t * string) list ref = ref []
(* The request being served, its project and its session. *)
let current : (Project.t * int * served) option ref = ref None
let reported = ref [] (* Latest first. *)
let strays = ref [] (* Latest first. *)
let count = ref 0
let ignored = ref 0

let start () =
  on := true;
  incr session;
  reported := [];
  strays := [];
  count := 0;
  ignored := 0

let stop () = on := false

(* A request made within a request of another project ends first. *)
let requests () =
  List.sort (fun r r' -> Int.compare r.number r'.number) !reported

let stray_reads () = List.rev !strays

let ignored_reads () = !ignored

let in_project project = Project.equal project (Project.current ())

(* An analysis started inside a request does not belong to this request. *)
let analysis f =
  let outer = !current in
  let finally () =
    analyses := List.tl !analyses;
    current := outer
  in
  analyses := Project.current () :: !analyses;
  current := None;
  Fun.protect ~finally f

let pass name f =
  passes := (Project.current (), name) :: !passes;
  Fun.protect ~finally:(fun () -> passes := List.tl !passes) f

(* The pass being run in the current project, if any. *)
let current_pass () =
  List.find_map
    (fun (project, name) -> if in_project project then Some name else None)
    !passes

let iterating () = List.exists in_project !analyses

(* Whether a read or a request in the current project is made after the
   iteration of its analysis: when Eva has results, and from the return of the
   iteration, while Eva is still computing, to the setting of its results.
   Eva computes only within [analysis] and in that interval. *)
let after_iteration () =
  not (iterating ()) &&
  match Self.ComputationState.get () with
  | Computing | Computed | Aborted -> true
  | NotComputed -> false

let serve served f =
  let outer = !current in
  current := Some (Project.current (), !session, served);
  Fun.protect ~finally:(fun () -> current := outer) f

(* The request being served in the current project, if any, with its
   session. A request made in another project is a request of its own. *)
let served_in_session () =
  match !current with
  | Some (project, session, served) when in_project project ->
    Some (session, served)
  | Some _ | None -> None

let served () = Option.map snd (served_in_session ())

let request pp f =
  if not !on || Option.is_some (served ()) then f ()
  else if iterating () then serve Ignored f
  else if not (after_iteration ()) then f ()
  else begin
    incr count;
    let number = !count in
    let description = Format.asprintf "%t" pp in
    let pass = current_pass () in
    let reads = ref [] in
    let started = !session in
    let record () =
      if started = !session then
        let reads = List.rev !reads in
        reported := { number; description; pass; reads } :: !reported
    in
    Fun.protect ~finally:record (fun () -> serve (Reported reads) f)
  end

let reading () =
  !on && (Option.is_some (served ()) || after_iteration ())

let read ~store access pp =
  let read () = { store; access; point = Format.asprintf "%t" pp } in
  match served_in_session () with
  | None ->
    if !on && after_iteration () then
      strays := { in_pass = current_pass (); read = read () } :: !strays
  | Some (started, _) when started <> !session -> ()
  | Some (_, Ignored) -> incr ignored
  | Some (_, Reported reads) -> reads := read () :: !reads

let pretty_callstack fmt callstack =
  let pretty_call fmt (kf, kinstr) =
    match kinstr with
    | Cil_types.Kglobal -> Kernel_function.pretty fmt kf
    | Kstmt stmt ->
      Format.fprintf fmt "%a :: %a" Kernel_function.pretty kf
        Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
  in
  let calls = List.rev (Callstack.to_call_list callstack) in
  Pretty_utils.pp_list ~pre:"" ~sep:" <- " ~suf:"" pretty_call fmt calls

let pretty_access fmt = function
  | Joined -> Format.pp_print_string fmt "joined state"
  | Callstack callstack ->
    Format.fprintf fmt "state of callstack %a" pretty_callstack callstack
  | Callstacks -> Format.pp_print_string fmt "callstacks"

let pretty_read fmt { store; access; point } =
  Format.fprintf fmt "read of the %s store: %a, %s" store pretty_access access
    point

let pretty_pass fmt = function
  | None -> ()
  | Some name -> Format.fprintf fmt " (pass: %s)" name

let pretty_request fmt { number; description; pass; reads } =
  Format.fprintf fmt "@[<v 2>request %d%a: %s" number pretty_pass pass
    description;
  begin match reads with
    | [] -> Format.fprintf fmt "@ no read"
    | _ -> List.iter (Format.fprintf fmt "@ %a" pretty_read) reads
  end;
  Format.fprintf fmt "@]"

let pretty_stray fmt { in_pass; read } =
  Format.fprintf fmt "@[<v 2>outside any request%a:@ %a@]" pretty_pass in_pass
    pretty_read read
