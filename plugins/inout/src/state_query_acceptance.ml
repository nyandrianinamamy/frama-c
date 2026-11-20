(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* Acceptance driver for Eva result queries. Prototype only. *)

open Cil_types

module Guard = Eva.Legacy_read_guard
module R = Eva.Results

type mode = Reference | Candidate | Trap of Guard.phase

let parse_mode name =
  match name with
  | "reference" -> Reference
  | "candidate" -> Candidate
  | _ ->
    let phase =
      if String.starts_with ~prefix:"trap:" name then
        Guard.phase_of_name (String.sub name 5 (String.length name - 5))
      else None
    in
    match phase with
    | Some phase -> Trap phase
    | None ->
      Inout_parameters.abort "unknown mode %S for %s" name
        Inout_parameters.QueryAcceptance.option_name

let log fmt = Format.printf ("[acceptance] " ^^ fmt ^^ "@.")

(* The statement labelled P, as in the prototype fixtures. *)
let target () =
  let is_p = function Label ("P", _, _) -> true | _ -> false in
  let find kf found =
    match found with
    | Some _ -> found
    | None when Kernel_function.is_definition kf ->
      let body = Kernel_function.get_definition kf in
      List.find_opt (fun s -> List.exists is_p s.labels) body.sallstmts
      |> Option.map (fun stmt -> kf, stmt)
    | None -> None
  in
  match Globals.Functions.fold find None with
  | Some target -> target
  | None -> Inout_parameters.abort "no statement labelled P"

(* {2 Records} *)

let output = ref None

let emit json =
  Option.iter (fun channel ->
      output_string channel (Yojson.Basic.to_string json);
      output_char channel '\n';
      flush channel)
    !output

let opt_string = function None -> `Null | Some s -> `String s

let json_of_read (read : Guard.read) =
  `Assoc [
    "phase", `String (Guard.phase_name read.phase);
    "reader", `String (Guard.reader_name read);
    "readers", `List (List.map (fun s -> `String s) read.readers);
    "access", `String (Guard.access_name read.access);
    "store", `String read.store;
    "point", `String read.point;
    "caller", opt_string read.caller;
  ]

(* Reads grouped by phase, reader, access and store, in order of first
   occurrence, with their count. *)
let group reads =
  let key (read : Guard.read) =
    read.phase, Guard.reader_name read, read.access, read.store
  in
  let counts = Hashtbl.create 17 in
  let add firsts read =
    match Hashtbl.find_opt counts (key read) with
    | Some n -> Hashtbl.replace counts (key read) (n + 1); firsts
    | None -> Hashtbl.add counts (key read) 1; read :: firsts
  in
  List.fold_left add [] reads
  |> List.rev_map (fun read -> read, Hashtbl.find counts (key read))

(* One line, for the summary on stdout. *)
let one_line text =
  String.split_on_char '\n' text
  |> List.map String.trim
  |> List.filter (fun s -> s <> "")
  |> String.concat "; "

let pretty_kf_status = function
  | Eva.Analysis.Unreachable -> "unreachable"
  | SpecUsed -> "specification used"
  | Builtin name -> "builtin " ^ name
  | Analyzed Complete -> "analyzed complete"
  | Analyzed Partial -> "analyzed partial"
  | Analyzed NoResults -> "analyzed without results"

let pretty_error = function
  | R.Bottom -> "error bottom"
  | R.Top -> "error top"
  | R.DisabledDomain -> "error disabled domain"

let pretty_result pretty = function
  | Ok v -> Format.asprintf "%a" pretty v
  | Error e -> pretty_error e

(* Same naming as the legacy-read guard: entry point, then callee@line. *)
let stack_name stack =
  let call (kf, kinstr) =
    match kinstr with
    | Kglobal -> None
    | Kstmt stmt ->
      Some (Format.asprintf "%a@%d" Kernel_function.pretty kf
              (Fileloc.line (Cil_datatype.Stmt.loc stmt)))
  in
  let entry = Kernel_function.get_name stack.Eva.Callstack.entry_point in
  String.concat "/"
    (entry :: List.filter_map call (Eva.Callstack.to_call_list stack))

(* {2 Calls} *)

(* Runs one public request and records its answer and the legacy reads it
   made. *)
let call ~id ~family ~request answer =
  let text, reads = Guard.observe answer in
  let observed = Guard.mode () <> Off in
  log "call %s legacy-reads=%s answer=%s" id
    (if observed then string_of_int (List.length reads) else "unobserved")
    (one_line text);
  emit (`Assoc [
      "kind", `String "call";
      "id", `String id;
      "family", `String family;
      "request", `String request;
      "answer", `String text;
      "reads",
      (if observed then `List (List.map json_of_read reads) else `Null);
    ])

let battery kf stmt =
  let kf_name = Kernel_function.get_name kf in
  let names stacks = List.map stack_name stacks |> List.sort compare in
  let stacks = R.(before stmt |> callstacks) in
  call ~id:"stacks.before-P" ~family:"enumeration"
    ~request:"Eva.Results.(before P |> callstacks)"
    (fun () -> String.concat " " (names R.(before stmt |> callstacks)));
  call ~id:"by_callstack.before-P" ~family:"enumeration"
    ~request:"Eva.Results.(before P |> by_callstack)"
    (fun () ->
       String.concat " " (names (List.map fst R.(before stmt |> by_callstack))));
  call ~id:("available." ^ kf_name) ~family:"availability"
    ~request:"Eva.Results.are_available f"
    (fun () -> string_of_bool (R.are_available kf));
  call ~id:("status." ^ kf_name) ~family:"availability"
    ~request:"Eva.Analysis.status f"
    (fun () -> pretty_kf_status (Eva.Analysis.status kf));
  call ~id:"reachable.P" ~family:"availability"
    ~request:"Eva.Results.is_reachable P"
    (fun () -> string_of_bool (R.is_reachable stmt));
  let stacks = List.sort (fun a b -> compare (stack_name a) (stack_name b))
      stacks in
  let per_stack id request req f =
    call ~id ~family:"getter" ~request (fun () -> f req);
    List.iter (fun stack ->
        call ~id:(id ^ "." ^ stack_name stack) ~family:"getter"
          ~request:(request ^ " |> in_callstack " ^ stack_name stack)
          (fun () -> f (R.in_callstack stack req)))
      stacks
  in
  let model req =
    pretty_result Cvalue.Model.pretty R.(get_cvalue_model_result req)
  in
  per_stack "model.before-P" "Eva.Results.(before P |> get_cvalue_model)"
    (R.before stmt) model;
  per_stack "model.after-P" "Eva.Results.(after P |> get_cvalue_model)"
    (R.after stmt) model;
  let globals =
    Globals.Vars.fold (fun vi _ acc -> if vi.vsource then vi :: acc else acc) []
    |> List.sort (fun a b -> compare a.vname b.vname)
  in
  List.iter (fun vi ->
      per_stack ("value." ^ vi.vname ^ ".before-P")
        ("Eva.Results.(before P |> eval_var " ^ vi.vname ^ " |> as_cvalue)")
        (R.before stmt)
        (fun req ->
           pretty_result Cvalue.V.pretty R.(eval_var vi req |> as_cvalue_result)))
    globals;
  call ~id:("model.start-of-" ^ kf_name) ~family:"getter"
    ~request:"Eva.Results.(at_start_of f |> get_cvalue_model)"
    (fun () -> model (R.at_start_of kf));
  call ~id:"model.initial" ~family:"getter"
    ~request:"Eva.Results.(at_start |> get_cvalue_model)"
    (fun () -> model R.at_start);
  call ~id:"export.get_results" ~family:"alias"
    ~request:"Eva.Eva_results.get_results ()"
    (fun () -> ignore (Eva.Eva_results.get_results ()); "exported");
  (* Sensitivity: a request on a supplied state must not read the store. *)
  call ~id:"supplied-state.eval" ~family:"supplied-state"
    ~request:"Eva.Results.(in_cvalue_state empty |> eval_exp (2+3))"
    (fun () ->
       let loc = Cil_datatype.Stmt.loc stmt in
       let exp =
         Cil.new_exp ~loc
           (BinOp (PlusA, Cil.integer ~loc 2, Cil.integer ~loc 3,
                   Cil_const.intType))
       in
       pretty_result Cvalue.V.pretty
         R.(in_cvalue_state Cvalue.Model.empty_map |> eval_exp exp
            |> as_cvalue_result))

(* {2 Header} *)

let header mode =
  let plugins = ref [] in
  Plugin.iter_on_plugins (fun p -> plugins := p.p_name :: !plugins);
  let config = [
    "-eva-domains", String.concat "," (Eva.Parameters.Domains.get ()
                                       |> Datatype.String.Set.elements);
    "-eva-slevel", string_of_int (Eva.Parameters.SLevel.get ());
    "-eva-memexec", string_of_bool (Eva.Parameters.Memexec.get ());
    "-eva-results", string_of_bool (Eva.Parameters.ResultsAll.get ());
    "-eva-join-results", string_of_bool (Eva.Parameters.JoinResults.get ());
    "-eva-no-results-domain",
    String.concat "," (Eva.Parameters.NoResultsDomain.get ()
                       |> Datatype.String.Set.elements);
    "-eva-no-results-function",
    Eva.Parameters.NoResultsFunction.As_string.get ();
  ] in
  let guard = match Guard.mode () with
    | Off -> "off" | Record -> "record"
    | Trap phases -> "trap:" ^ String.concat "," (List.map Guard.phase_name phases)
  in
  log "mode=%s guard=%s" mode guard;
  log "config %s"
    (String.concat " " (List.map (fun (k, v) -> k ^ "=" ^ v) config));
  emit (`Assoc [
      "kind", `String "header";
      "mode", `String mode;
      "guard", `String guard;
      "argv", `List (Array.to_list Sys.argv |> List.map (fun s -> `String s));
      "plugins", `List (List.sort compare !plugins
                        |> List.map (fun s -> `String s));
      "config", `Assoc (List.map (fun (k, v) -> k, `String v) config);
      "inputs", `List (Kernel.Files.get ()
                       |> List.map (fun f -> `String (Filepath.to_string f)));
    ])

let execution () =
  let reads = Guard.reads () in
  List.iter (fun ((read : Guard.read), count) ->
      log "execution phase=%s reader=%s access=%s store=%s"
        (Guard.phase_name read.phase) (Guard.reader_name read)
        (Guard.access_name read.access) read.store;
      emit (`Assoc [
          "kind", `String "execution";
          "count", `Int count;
          "first", json_of_read read;
        ]))
    (group reads)

(* Positive control: one known request in the request phase. *)
let control stmt =
  log "control Eva.Results.(before P |> get_cvalue_model)";
  ignore R.(before stmt |> get_cvalue_model);
  log "control not trapped"

let compute () =
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ();
  (* The final values are printed only when Eva is enabled. *)
  Eva.Parameters.Eva.set true;
  Eva.Analysis.compute ()

let run () =
  match Inout_parameters.QueryAcceptance.get () with
  | "" -> ()
  | name ->
    let mode = parse_mode name in
    begin match Inout_parameters.QueryAcceptanceOutput.get () with
      | "" -> ()
      | file -> output := Some (open_out file)
    end;
    Guard.clear ();
    begin match mode with
      | Reference ->
        Eva.Parameters.Memexec.set false;
        Guard.arm Off
      | Candidate -> Guard.arm Record
      | Trap phase -> Guard.arm (Trap [phase])
    end;
    header name;
    compute ();
    let kf, stmt = target () in
    match mode with
    | Trap Request -> control stmt
    | Trap phase ->
      log "control not trapped in phase %s" (Guard.phase_name phase)
    | Reference | Candidate ->
      execution ();
      battery kf stmt;
      Option.iter close_out !output

let () = Boot.Main.extend run
