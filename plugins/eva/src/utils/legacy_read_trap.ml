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
  reads: read list;
}

(* The request being served: reported with its reads so far, latest first,
   or started during an analysis. *)
type served =
  | Reported of read list ref
  | Ignored

let on = ref false
(* Projects whose analysis is running, innermost first. *)
let analyses : Project.t list ref = ref []
(* The request being served and its project. *)
let current : (Project.t * served) option ref = ref None
let reported = ref [] (* Latest first. *)
let count = ref 0
let ignored = ref 0

let start () =
  on := true;
  reported := [];
  count := 0;
  ignored := 0

let stop () = on := false

(* A request made within a request of another project ends first. *)
let requests () =
  List.sort (fun r r' -> Int.compare r.number r'.number) !reported

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

let serve served f =
  let outer = !current in
  current := Some (Project.current (), served);
  Fun.protect ~finally:(fun () -> current := outer) f

(* The request being served in the current project, if any. A request made
   in another project is a request of its own. *)
let served () =
  match !current with
  | Some (project, served) when in_project project -> Some served
  | Some _ | None -> None

let request pp f =
  if not !on || Option.is_some (served ()) then f ()
  else if List.exists in_project !analyses then serve Ignored f
  else if not (Self.is_computed ()) then f ()
  else begin
    incr count;
    let number = !count in
    let description = Format.asprintf "%t" pp in
    let reads = ref [] in
    let record () =
      let reads = List.rev !reads in
      reported := { number; description; reads } :: !reported
    in
    Fun.protect ~finally:record (fun () -> serve (Reported reads) f)
  end

let reading () = !on && Option.is_some (served ())

let read ~store access pp =
  match served () with
  | None -> ()
  | Some Ignored -> incr ignored
  | Some (Reported reads) ->
    let point = Format.asprintf "%t" pp in
    reads := { store; access; point } :: !reads

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

let pretty_request fmt { number; description; reads } =
  Format.fprintf fmt "@[<v 2>request %d: %s" number description;
  begin match reads with
    | [] -> Format.fprintf fmt "@ no read"
    | _ -> List.iter (Format.fprintf fmt "@ %a" pretty_read) reads
  end;
  Format.fprintf fmt "@]"
