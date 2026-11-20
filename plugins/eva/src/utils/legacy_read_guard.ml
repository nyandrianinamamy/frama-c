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

let arm mode = current_mode := mode
let mode () = !current_mode

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
    match mode with
    | Trap phases when List.mem read.phase phases ->
      trapped_read := Some read;
      current_mode := Record;
      Self.abort "legacy result-store read trapped: %a" pretty_read read
    | Off | Record | Trap _ -> ()

let reads () = List.rev !log

let clear () =
  log := [];
  logged := 0;
  trapped_read := None

let observe f =
  let before = !logged in
  let result = f () in
  let rec take n list =
    if n <= 0 then [] else
      match list with
      | [] -> []
      | x :: tail -> x :: take (n - 1) tail
  in
  result, List.rev (take (!logged - before) !log)

let trapped () = !trapped_read
