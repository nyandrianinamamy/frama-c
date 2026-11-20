(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type phase =
  | Initialization
  | Analysis
  | Collection
  | Post_analysis
  | Request

type access = Getter | Enumeration | Availability

type read = {
  phase: phase;
  access: access;
  store: string;
  point: string;
  readers: string list;
  caller: string option;
}

type mode = Off | Record | Trap of phase list

let current_mode = ref Off
let current_phase = ref Request
let current_readers = ref [] (* innermost first *)
let log = ref [] (* latest first *)
let logged = ref 0
let trapped_read = ref None
let forbidden = ref []

let arm mode = current_mode := mode; forbidden := []
let mode () = !current_mode
let forbid labels = forbidden := labels

let scoped reference value f =
  let saved = !reference in
  reference := value;
  Fun.protect ~finally:(fun () -> reference := saved) f

(* Scopes cost nothing while the guard is off. *)
let during phase f =
  match !current_mode with
  | Off -> f ()
  | Record | Trap _ -> scoped current_phase phase f

let reader label f =
  match !current_mode with
  | Off -> f ()
  | Record | Trap _ -> scoped current_readers (label :: !current_readers) f

let phase_name = function
  | Initialization -> "initialization"
  | Analysis -> "analysis"
  | Collection -> "collection"
  | Post_analysis -> "post-analysis"
  | Request -> "request"

let phase_of_name name =
  List.find_opt (fun phase -> phase_name phase = name)
    [ Initialization; Analysis; Collection; Post_analysis; Request ]

let access_name = function
  | Getter -> "getter"
  | Enumeration -> "enumeration"
  | Availability -> "availability"

let reader_name read =
  match read.readers with
  | [] -> "unlabelled"
  | outermost :: _ -> outermost

let pretty_read fmt read =
  Format.fprintf fmt "phase=%s reader=%s access=%s store=%s point=%s"
    (phase_name read.phase) (reader_name read) (access_name read.access)
    read.store read.point;
  match read.readers with
  | _ :: (_ :: _ as inner) ->
    Format.fprintf fmt " via=%s" (String.concat ">" inner)
  | _ -> ()

(* Frames of Eva, of the kernel and of the standard library are skipped. *)
let internal name =
  List.exists (fun prefix -> String.starts_with ~prefix name)
    [ "Eva__"; "Eva."; "Fclib"; "Frama_c_kernel"; "Stdlib"; "Camlinternal";
      "Std_exit" ]

(* Reaching the frames of Eva's analysis first means that Eva itself is
   the reader, whatever code started the analysis. *)
let analysis name = String.starts_with ~prefix:"Eva__Analysis." name

let caller () =
  let slots = Printexc.(backtrace_slots (get_callstack 128)) in
  let names = Option.fold ~none:[||] ~some:(Array.map Printexc.Slot.name) slots in
  Array.to_seq names
  |> Seq.filter_map Fun.id
  |> Seq.find (fun name -> analysis name || not (internal name))
  |> function
  | Some name when analysis name -> None
  | found -> found

let notify access ~store point =
  match !current_mode with
  | Off -> ()
  | Record | Trap _ as mode ->
    let read = {
      phase = !current_phase; access; store;
      point = Format.asprintf "%t" point;
      readers = List.rev !current_readers;
      caller = caller ();
    } in
    log := read :: !log;
    incr logged;
    let trapped =
      match mode with
      | Trap phases -> List.mem read.phase phases
      | Off | Record -> false
    in
    let by_forbidden_reader =
      List.exists (fun label -> List.mem label read.readers) !forbidden
    in
    if trapped || by_forbidden_reader then begin
      trapped_read := Some read;
      current_mode := Record;
      forbidden := [];
      Self.abort "legacy result-store read trapped: %a" pretty_read read
    end

type resolution = {
  resolved_phase: phase;
  resolved_point: string;
  visits: string;
  resolved_readers: string list;
}

let resolution_log = ref [] (* latest first *)
let resolved_count = ref 0

let resolved point visits =
  match !current_mode with
  | Off -> ()
  | Record | Trap _ ->
    let resolution = {
      resolved_phase = !current_phase;
      resolved_point = Format.asprintf "%t" point;
      visits = Format.asprintf "%t" visits;
      resolved_readers = List.rev !current_readers;
    } in
    resolution_log := resolution :: !resolution_log;
    incr resolved_count

let reads () = List.rev !log
let resolutions () = List.rev !resolution_log

let clear () =
  log := [];
  logged := 0;
  trapped_read := None;
  resolution_log := [];
  resolved_count := 0

let rec take n list =
  if n <= 0 then [] else
    match list with
    | [] -> []
    | x :: tail -> x :: take (n - 1) tail

let observe f =
  let before = !logged in
  let result = f () in
  result, List.rev (take (!logged - before) !log)

let observe_resolutions f =
  let before = !resolved_count in
  let result = f () in
  result, List.rev (take (!resolved_count - before) !resolution_log)

let trapped () = !trapped_read
