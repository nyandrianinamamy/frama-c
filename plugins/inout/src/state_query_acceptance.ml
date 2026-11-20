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

type mode =
  | Reference
  | Candidate
  | Native
  | Wrong_producer
  | Trap of Guard.phase

let parse_mode name =
  match name with
  | "reference" -> Reference
  | "candidate" -> Candidate
  | "native" -> Native
  | "wrong-producer" -> Wrong_producer
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

let json_of_resolution (r : Guard.resolution) =
  `Assoc [
    "phase", `String (Guard.phase_name r.resolved_phase);
    "point", `String r.resolved_point;
    "visits", `String r.visits;
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

(* The path that should serve a request once the hit log is on. *)
type expect =
  | Legacy    (* reads the legacy store *)
  | Resolver  (* served by the resolver, without legacy read *)
  | No_read   (* reads neither, such as a supplied state *)

let expect_name = function
  | Legacy -> "legacy"
  | Resolver -> "resolver"
  | No_read -> "none"

(* Native answers, compared in-process by the native mode. *)
type native =
  | Model of Cvalue.Model.t R.result
  | Value of Cvalue.V.t R.result
  | Text

let native_equal a b =
  let equal_result equal a b =
    match a, b with
    | Ok a, Ok b -> equal a b
    | Error a, Error b -> a = b
    | Ok _, Error _ | Error _, Ok _ -> false
  in
  match a, b with
  | Model a, Model b -> Some (equal_result Cvalue.Model.equal a b)
  | Value a, Value b -> Some (equal_result Cvalue.V.equal a b)
  | _ -> None

type answer = {
  id: string;
  text: string;
  native: native;
  reads: Guard.read list;
  resolutions: Guard.resolution list;
}

(* Answers of the current battery, latest first. *)
let answers = ref []

(* Number of reads attributed to the execution and to the calls. *)
let attributed = ref 0

(* Whether call records are written; the native mode writes its own. *)
let quiet = ref false

(* Runs one public request and records its answer, the legacy reads it
   made and the resolutions that served it. *)
let call ~id ~family ~request ~expect answer =
  let (text, native), reads, resolutions =
    let (result, resolutions), reads =
      Guard.observe (fun () -> Guard.observe_resolutions answer)
    in
    result, reads, resolutions
  in
  attributed := !attributed + List.length reads;
  answers := { id; text; native; reads; resolutions } :: !answers;
  let observed = Guard.mode () <> Off in
  if not !quiet then begin
    let count list =
      if observed then string_of_int (List.length list) else "unobserved"
    in
    log "call %s legacy-reads=%s resolved=%s answer=%s" id (count reads)
      (count resolutions) (one_line text);
    emit (`Assoc [
        "kind", `String "call";
        "id", `String id;
        "family", `String family;
        "request", `String request;
        "expect", `String (expect_name expect);
        "answer", `String text;
        "reads",
        (if observed then `List (List.map json_of_read reads) else `Null);
        "resolved",
        (if observed then `List (List.map json_of_resolution resolutions)
         else `Null);
      ])
  end

let text answer () = answer (), Text

let model req =
  let result = R.get_cvalue_model_result req in
  pretty_result Cvalue.Model.pretty result, Model result

let by_stack_name stacks =
  List.sort (fun a b -> compare (stack_name a) (stack_name b)) stacks

let line stmt = Fileloc.line (Cil_datatype.Stmt.loc stmt)

(* The calls statements of defined functions, in the order of the file. *)
let call_sites () =
  let sites = ref [] in
  Globals.Functions.iter (fun caller ->
      if Kernel_function.is_definition caller then
        List.iter (fun stmt ->
            match stmt.skind with
            | Instr (Call (_, callee, _, _)) ->
              begin match Kernel_function.get_called callee with
                | Some kf when Kernel_function.is_definition kf ->
                  sites := (stmt, kf) :: !sites
                | _ -> ()
              end
            | _ -> ())
          (Kernel_function.get_definition caller).sallstmts);
  List.sort (fun (s1, _) (s2, _) -> compare (line s1) (line s2)) !sites

let battery kf stmt =
  let kf_name = Kernel_function.get_name kf in
  let names stacks = List.map stack_name stacks |> List.sort compare in
  (* The stacks used by the per-stack requests are the answer of this
     request, so that its reads are attributed. *)
  let stacks = ref [] in
  call ~id:"stacks.before-P" ~family:"enumeration" ~expect:Legacy
    ~request:"Eva.Results.(before P |> callstacks)"
    (text (fun () ->
         stacks := R.(before stmt |> callstacks);
         String.concat " " (names !stacks)));
  call ~id:"by_callstack.before-P" ~family:"enumeration" ~expect:Legacy
    ~request:"Eva.Results.(before P |> by_callstack)"
    (text (fun () ->
         String.concat " "
           (names (List.map fst R.(before stmt |> by_callstack)))));
  call ~id:("available." ^ kf_name) ~family:"availability" ~expect:Legacy
    ~request:"Eva.Results.are_available f"
    (text (fun () -> string_of_bool (R.are_available kf)));
  call ~id:("status." ^ kf_name) ~family:"availability" ~expect:Legacy
    ~request:"Eva.Analysis.status f"
    (text (fun () -> pretty_kf_status (Eva.Analysis.status kf)));
  call ~id:"reachable.P" ~family:"availability" ~expect:Legacy
    ~request:"Eva.Results.is_reachable P"
    (text (fun () -> string_of_bool (R.is_reachable stmt)));
  let stacks = by_stack_name !stacks in
  (* The unfiltered request reads the legacy store; the request on each
     supplied stack goes through the resolver. *)
  let per_stack id request req f =
    call ~id ~family:"getter" ~request ~expect:Legacy (fun () -> f req);
    List.iter (fun stack ->
        call ~id:(id ^ "." ^ stack_name stack) ~family:"supplied-stack"
          ~expect:Resolver
          ~request:(request ^ " |> in_callstack " ^ stack_name stack)
          (fun () -> f (R.in_callstack stack req)))
      stacks
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
           let result = R.(eval_var vi req |> as_cvalue_result) in
           pretty_result Cvalue.V.pretty result, Value result))
    globals;
  call ~id:("model.start-of-" ^ kf_name) ~family:"getter" ~expect:Legacy
    ~request:"Eva.Results.(at_start_of f |> get_cvalue_model)"
    (fun () -> model (R.at_start_of kf));
  call ~id:"model.initial" ~family:"getter" ~expect:Legacy
    ~request:"Eva.Results.(at_start |> get_cvalue_model)"
    (fun () -> model R.at_start);
  (* Position adapters at P, on each supplied stack. *)
  List.iter (fun stack ->
      let pos = Eva.Position.local stmt stack in
      call ~id:("model.before-pos-P." ^ stack_name stack)
        ~family:"supplied-stack" ~expect:Resolver
        ~request:("Eva.Results.(before_pos (P, " ^ stack_name stack
                  ^ ") |> get_cvalue_model)")
        (fun () -> model (R.before_pos pos));
      call ~id:("model.after-pos-P." ^ stack_name stack)
        ~family:"supplied-stack" ~expect:Resolver
        ~request:("Eva.Results.(after_pos (P, " ^ stack_name stack
                  ^ ") |> get_cvalue_model)")
        (fun () -> model (R.after_pos pos)))
    stacks;
  (* Initial state, entry point and root call of the analysis. *)
  let main = fst (Globals.entry_point ()) in
  let root = Eva.Callstack.init ~thread:Eva.Thread.main_id ~entry_point:main in
  call ~id:("model.initial." ^ stack_name root) ~family:"supplied-stack"
    ~expect:Resolver
    ~request:("Eva.Results.(at_start |> in_callstack " ^ stack_name root
              ^ " |> get_cvalue_model)")
    (fun () -> model R.(at_start |> in_callstack root));
  let root_pos =
    Eva.Position.root_call ~thread:Eva.Thread.main_id ~entry_point:main
  in
  call ~id:"model.before-pos-root" ~family:"supplied-stack" ~expect:Resolver
    ~request:"Eva.Results.(before_pos (root call) |> get_cvalue_model)"
    (fun () -> model (R.before_pos root_pos));
  call ~id:"model.after-pos-root" ~family:"supplied-stack" ~expect:Resolver
    ~request:"Eva.Results.(after_pos (root call) |> get_cvalue_model)"
    (fun () -> model (R.after_pos root_pos));
  (* Function entry, first statement and return of each analyzed function,
     on each of its stacks. The first statement shows the entries that
     survive the preconditions. *)
  let functions =
    Globals.Functions.fold (fun kf acc ->
        if Kernel_function.is_definition kf then kf :: acc else acc) []
    |> List.sort (fun a b ->
        compare (Kernel_function.get_name a) (Kernel_function.get_name b))
  in
  List.iter (fun kf ->
      let name = Kernel_function.get_name kf in
      let kf_stacks = ref [] in
      call ~id:("stacks.start-of-" ^ name) ~family:"enumeration"
        ~expect:Legacy
        ~request:("Eva.Results.(at_start_of " ^ name ^ " |> callstacks)")
        (text (fun () ->
             kf_stacks := by_stack_name R.(at_start_of kf |> callstacks);
             String.concat " " (List.map stack_name !kf_stacks)));
      let first = Kernel_function.find_first_stmt kf in
      List.iter (fun stack ->
          let on_stack id request req =
            call ~id:(id ^ "." ^ stack_name stack) ~family:"supplied-stack"
              ~expect:Resolver
              ~request:("Eva.Results.(" ^ request ^ " |> in_callstack "
                        ^ stack_name stack ^ " |> get_cvalue_model)")
              (fun () -> model (R.in_callstack stack req))
          in
          on_stack ("model.start-of-" ^ name) ("at_start_of " ^ name)
            (R.at_start_of kf);
          on_stack ("model.body-entry-of-" ^ name)
            ("before (first statement of " ^ name ^ ")") (R.before first);
          on_stack ("model.end-of-" ^ name) ("at_end_of " ^ name)
            (R.at_end_of kf);
          if Eva.Hit_log.recording () || Guard.mode () <> Off then
            let visits =
              Format.asprintf "%a" Eva.Hit_log.pretty_visits stack
            in
            if visits <> "" && not !quiet then begin
              log "visits %s.%s %s" name (stack_name stack) (one_line visits);
              emit (`Assoc [
                  "kind", `String "visits";
                  "function", `String name;
                  "stack", `String (stack_name stack);
                  "visits", `String visits;
                ])
            end)
        !kf_stacks)
    functions;
  (* InOut: the callwise inputs and outputs of each call, collected during
     the analysis from the live inputs and point states. *)
  List.iter (fun (stmt, kf) ->
      let name = Kernel_function.get_name kf in
      call ~id:(Format.sprintf "inout.call-%s@%d" name (line stmt))
        ~family:"inout" ~expect:No_read
        ~request:"Inout.get_precise_inout ~stmt f"
        (text (fun () ->
             let inout = Operational_inputs.get_internal_precise ~stmt kf in
             Format.asprintf "%a@\nLogic inputs:@ %a" Inout_type.pretty inout
               Memory_zone.pretty inout.over_logic_inputs)))
    (call_sites ());
  call ~id:"export.get_results" ~family:"alias" ~expect:Legacy
    ~request:"Eva.Eva_results.get_results ()"
    (text (fun () -> ignore (Eva.Eva_results.get_results ()); "exported"));
  (* Sensitivity: a request on a supplied state must not read the store. *)
  call ~id:"supplied-state.eval" ~family:"supplied-state" ~expect:No_read
    ~request:"Eva.Results.(in_cvalue_state empty |> eval_exp (2+3))"
    (fun () ->
       let loc = Cil_datatype.Stmt.loc stmt in
       let exp =
         Cil.new_exp ~loc
           (BinOp (PlusA, Cil.integer ~loc 2, Cil.integer ~loc 3,
                   Cil_const.intType))
       in
       let result =
         R.(in_cvalue_state Cvalue.Model.empty_map |> eval_exp exp
            |> as_cvalue_result)
       in
       pretty_result Cvalue.V.pretty result, Value result)

(* {2 Header} *)

let header mode =
  let plugins = ref [] in
  Plugin.iter_on_plugins (fun p -> plugins := p.p_name :: !plugins);
  let config = [
    "-eva-domains", String.concat "," (Eva.Parameters.Domains.get ()
                                       |> Datatype.String.Set.elements);
    "-eva-slevel", string_of_int (Eva.Parameters.SLevel.get ());
    "-eva-memexec", string_of_bool (Eva.Parameters.Memexec.get ());
    "-eva-hit-log", string_of_bool (Eva.Parameters.HitLog.get ());
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
  attributed := List.length reads;
  List.iter (fun ((read : Guard.read), count) ->
      log "execution phase=%s reader=%s access=%s store=%s"
        (Guard.phase_name read.phase) (Guard.reader_name read)
        (Guard.access_name read.access) read.store;
      emit (`Assoc [
          "kind", `String "execution";
          "count", `Int count;
          "first", json_of_read read;
        ]))
    (group reads);
  (* Collection reads by reader and caller: a plug-in that collects from the
     live inputs makes no read of its own. *)
  let collection =
    List.filter (fun (r : Guard.read) -> r.phase = Collection) reads
  in
  let key (r : Guard.read) =
    Guard.reader_name r, Option.value ~default:"" r.caller
  in
  let counts = Hashtbl.create 7 in
  List.iter (fun r ->
      let n = Option.value ~default:0 (Hashtbl.find_opt counts (key r)) in
      Hashtbl.replace counts (key r) (n + 1))
    collection;
  let rows =
    Hashtbl.fold (fun (reader, caller) n acc -> (reader, caller, n) :: acc)
      counts []
    |> List.sort compare
  in
  emit (`Assoc [
      "kind", `String "collection";
      "reads", `List (List.map (fun (reader, caller, n) ->
          `Assoc [ "reader", `String reader; "caller", `String caller;
                   "count", `Int n ])
          rows);
    ])

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

(* The reference is fresh-only and reads the legacy store alone. *)
let legacy_reference () =
  Eva.Parameters.Memexec.set false;
  Eva.Parameters.HitLog.set false;
  Guard.arm Off

let accounting () =
  let logged = List.length (Guard.reads ()) in
  log "accounting logged=%d attributed=%d" logged !attributed;
  emit (`Assoc [
      "kind", `String "accounting";
      "logged", `Int logged;
      "attributed", `Int !attributed;
    ])

(* Native mode: the fresh-only reference and the candidate run in the same
   process, on the same AST, so that their models are compared with the
   native equality of Cvalue. *)
let native kf stmt =
  quiet := true;
  legacy_reference ();
  (* The guard does not change the answers: record the reads of the
     reference too, to show that it took the legacy path. *)
  Guard.arm Record;
  compute ();
  battery kf stmt;
  let reference = List.rev !answers in
  answers := [];
  Eva.Parameters.HitLog.set true;
  Guard.clear ();
  Guard.arm Record;
  compute ();
  battery kf stmt;
  let candidate = List.rev !answers in
  let find id = List.find_opt (fun a -> a.id = id) candidate in
  let compared = ref 0 and differing = ref 0 in
  List.iter (fun expected ->
      match find expected.id with
      | None ->
        log "native %s missing" expected.id;
        incr differing
      | Some observed ->
        match native_equal expected.native observed.native with
        | None -> ()
        | Some equal ->
          incr compared;
          if not equal then incr differing;
          log "native %s equal=%b reference-reads=%d reference-resolved=%d \
               legacy-reads=%d resolved=%d" expected.id equal
            (List.length expected.reads) (List.length expected.resolutions)
            (List.length observed.reads) (List.length observed.resolutions);
          emit (`Assoc [
              "kind", `String "native";
              "id", `String expected.id;
              "equal", `Bool equal;
              "expected", `String expected.text;
              "observed", `String observed.text;
              "reference_reads", `Int (List.length expected.reads);
              "reference_resolved",
              `List (List.map json_of_resolution expected.resolutions);
              "reads", `List (List.map json_of_read observed.reads);
              "resolved",
              `List (List.map json_of_resolution observed.resolutions);
            ]))
    reference;
  log "native compared=%d differing=%d" !compared !differing;
  emit (`Assoc [
      "kind", `String "native-summary";
      "compared", `Int !compared;
      "differing", `Int !differing;
    ])

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
      | Reference -> legacy_reference ()
      | Candidate | Native -> Guard.arm Record
      | Wrong_producer ->
        Eva.Hit_log.set_wrong_producer_control true;
        Guard.arm Record
      | Trap phase -> Guard.arm (Trap [phase])
    end;
    header name;
    begin match mode with
      | Native ->
        let kf, stmt = target () in
        native kf stmt
      | _ ->
        compute ();
        let kf, stmt = target () in
        match mode with
        | Trap Request -> control stmt
        | Trap phase ->
          log "control not trapped in phase %s" (Guard.phase_name phase)
        | Reference | Candidate | Wrong_producer | Native ->
          execution ();
          battery kf stmt;
          (* Every logged read must belong to the execution or to one
             call. *)
          accounting ()
    end;
    Option.iter close_out !output

let () = Boot.Main.extend run
