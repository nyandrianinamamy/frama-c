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
  (** The continuous trap: every legacy read, in any phase, aborts Eva. The
      guard is armed once, before the analysis, and never changed. *)
  | Record_reads
  (** Every legacy read is logged; none aborts. *)
  | Native
  | Wrong_producer
  | Trap of Guard.phase
  | Tail_probe
  (** The candidate, then one request on cleared results, which must
      abort. *)
  | Store_check
  (** The analysis records the hit log, which then declines every request:
      the requests read the legacy store, as written during the analysis.
      Reads are logged. *)
  | Perturb_calls
  (** The hit log exports wrong statuses and callers. Reads are logged. *)
  | Restore_check
  (** The candidate, whose hit log declines every request once a snapshot
      of its results is restored: the requests after the restore read the
      legacy tables that the exported payload wrote. Reads are logged. *)

(* The requests made after the analysis: the battery around the statement
   labelled P, the reachability battery on every labelled statement
   ([reach-] modes), or the battery of the plug-in readers and of Eva's
   semantic reports ([plugins-] modes). *)
type battery = Point_battery | Reach_battery | Plugin_battery

let rec parse_mode name =
  let reach = "reach-" and plugins = "plugins-" in
  let suffix prefix =
    let len = String.length prefix in
    String.sub name len (String.length name - len)
  in
  if String.starts_with ~prefix:reach name then
    match parse_mode (suffix reach) with
    | Point_battery,
      (Reference | Candidate | Record_reads | Native | Restore_check as mode)
      ->
      Reach_battery, mode
    | _ ->
      Inout_parameters.abort "unknown mode %S for %s" name
        Inout_parameters.QueryAcceptance.option_name
  else if String.starts_with ~prefix:plugins name then
    match parse_mode (suffix plugins) with
    | Point_battery,
      (Reference | Candidate | Record_reads | Native | Wrong_producer
      | Tail_probe | Store_check | Perturb_calls | Restore_check as mode) ->
      Plugin_battery, mode
    | _ ->
      Inout_parameters.abort "unknown mode %S for %s" name
        Inout_parameters.QueryAcceptance.option_name
  else
    let mode =
      match name with
      | "reference" -> Reference
      | "candidate" -> Candidate
      | "record" -> Record_reads
      | "native" -> Native
      | "wrong-producer" -> Wrong_producer
      | "tail-probe" -> Tail_probe
      | "store-check" -> Store_check
      | "perturb-calls" -> Perturb_calls
      | "restore-check" -> Restore_check
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
    in
    Point_battery, mode

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

(* The path that should serve a request once the hit log is on. No request
   is expected on the legacy store any more. *)
type expect =
  | Resolver  (* served by the resolver, without legacy read *)
  | No_read   (* reads neither, such as a supplied state *)

let expect_name = function
  | Resolver -> "resolver"
  | No_read -> "none"

(* Native answers, compared in-process by the native mode. *)
type native =
  | Model of Cvalue.Model.t R.result
  | Value of Cvalue.V.t R.result
  | Inout of Inout_type.t
  | Uninit of Cvalue.V_Or_Uninitialized.t
  | Location of Locations.t R.result
  | Zone of Memory_zone.t R.result
  | Deps of Eva.Deps.t
  | Callees of Kernel_function.t list R.result
  | Stacks of Eva.Callstack.t list (* in the order of the answer *)
  | Alarms of Alarms.t list
  | Flag of bool
  | Several of native list
  | Text

let rec native_equal a b =
  let equal_result equal a b =
    match a, b with
    | Ok a, Ok b -> equal a b
    | Error a, Error b -> a = b
    | Ok _, Error _ | Error _, Ok _ -> false
  in
  match a, b with
  | Model a, Model b -> Some (equal_result Cvalue.Model.equal a b)
  | Value a, Value b -> Some (equal_result Cvalue.V.equal a b)
  | Inout a, Inout b -> Some (Inout_type.equal a b)
  | Uninit a, Uninit b -> Some (Cvalue.V_Or_Uninitialized.equal a b)
  | Location a, Location b -> Some (equal_result Locations.equal a b)
  | Zone a, Zone b -> Some (equal_result Memory_zone.equal a b)
  | Deps a, Deps b -> Some (Eva.Deps.equal a b)
  | Callees a, Callees b ->
    Some (equal_result (List.equal Kernel_function.equal) a b)
  | Stacks a, Stacks b -> Some (List.equal Eva.Callstack.equal a b)
  | Alarms a, Alarms b -> Some (List.equal Alarms.equal a b)
  | Flag a, Flag b -> Some (a = b)
  | Several a, Several b when List.compare_lengths a b = 0 ->
    let parts = List.map2 native_equal a b |> List.filter_map Fun.id in
    if parts = [] then None else Some (List.for_all Fun.id parts)
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
  (* A request made outside the analysis counts as an entry of the request
     phase. *)
  let answer () =
    if Guard.phase () = Request then Guard.during Request answer
    else answer ()
  in
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

(* Whether the results are computed, and the state of the computation. *)
let computation_requests ~prefix ~suffix =
  call ~id:(prefix ^ "analysis.is_computed") ~family:"availability"
    ~expect:Resolver ~request:("Eva.Analysis.is_computed ()" ^ suffix)
    (fun () ->
       let computed = Eva.Analysis.is_computed () in
       string_of_bool computed, Flag computed);
  call ~id:(prefix ^ "analysis.computation_state") ~family:"availability"
    ~expect:Resolver
    ~request:("Eva.Analysis.current_computation_state ()" ^ suffix)
    (text (fun () ->
         match Eva.Analysis.current_computation_state () with
         | NotComputed -> "not computed"
         | Computing -> "computing"
         | Computed -> "computed"
         | Aborted -> "aborted"))

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

(* {2 Stack selection and evaluation order} *)

(* What the selection battery evaluates before P: the expressions assigned
   in the block of the statement labelled E, and the callees of its calls.
   The block is never executed. *)
type probe =
  | Exp of exp
  | Callee of lhost

let probes () =
  let is_e = function Label ("E", _, _) -> true | _ -> false in
  let find kf found =
    match found with
    | Some _ -> found
    | None when Kernel_function.is_definition kf ->
      let body = Kernel_function.get_definition kf in
      List.find_opt (fun s -> List.exists is_e s.labels) body.sallstmts
    | None -> None
  in
  let probe stmt =
    match stmt.skind with
    | Instr (Set (_, e, _)) -> Some (Exp e)
    | Instr (Call (_, host, _, _)) -> Some (Callee host)
    | _ -> None
  in
  (* CIL can attach the label to an empty statement before the block. *)
  let rec block stmt =
    match stmt.skind, stmt.succs with
    | If (_, block, _, _), _ -> List.filter_map probe block.bstmts
    | Instr (Skip _), [ next ] -> block next
    | _ -> []
  in
  Globals.Functions.fold find None |> Option.fold ~none:[] ~some:block

let exp_name e =
  Format.asprintf "%a" Printer.pp_exp e
  |> String.split_on_char ' ' |> String.concat ""

let pretty_alarms = function
  | [] -> "none"
  | alarms ->
    String.concat ", " (List.map (Format.asprintf "%a" Alarms.pretty) alarms)

let pretty_callees = function
  | Ok kfs -> String.concat " " (List.map Kernel_function.get_name kfs)
  | Error e -> pretty_error e

(* The selections of a request at P. [stacks] reach P, sorted by name;
   [unreached] are stacks of the function of P that do not reach it. Each
   selection has a name, its text in the requests and its transformation. *)
let selections stacks unreached =
  let all = [
    "selector-all", "in_callstacks (all stacks)", R.in_callstacks stacks;
    "filter-all", "filter_callstack (fun _ -> true)",
    R.filter_callstack (fun _ -> true);
  ] in
  let singletons =
    List.map (fun s ->
        "stack:" ^ stack_name s, "in_callstack " ^ stack_name s,
        R.in_callstack s)
      stacks
  in
  let partial =
    match stacks with
    | first :: second :: _ :: _ ->
      [ "selector-two",
        "in_callstacks [" ^ stack_name first ^ "; " ^ stack_name second ^ "]",
        R.in_callstacks [ first; second ];
        "filter-drop-first",
        "filter_callstack (fun cs -> cs <> " ^ stack_name first ^ ")",
        R.filter_callstack (fun cs -> not (Eva.Callstack.equal cs first)) ]
    | _ -> []
  in
  let none = R.filter_callstack (fun _ -> false) in
  let unreached =
    match unreached with
    | [] -> []
    | _ ->
      [ "selector-unreached",
        "in_callstacks [" ^ String.concat "; " (List.map stack_name unreached)
        ^ "]",
        R.in_callstacks unreached ]
  in
  let rejected =
    match stacks with
    | [] -> []
    | first :: _ ->
      [ "stack-rejected",
        "in_callstack " ^ stack_name first
        ^ " |> filter_callstack (fun _ -> false)",
        (fun r -> none (R.in_callstack first r)) ]
  in
  let empty =
    unreached @ rejected
    @ [ "filter-none", "filter_callstack (fun _ -> false)", none ]
  in
  ("unfiltered", "", Fun.id) :: singletons @ all @ partial @ empty

(* The evaluation families of [probe] on [req]. *)
let evaluate ~id ~request ~expect probe req =
  let request family arg = "Eva.Results.(" ^ request ^ " |> " ^ family ^ " "
                           ^ arg ^ ")" in
  match probe with
  | Callee host ->
    let name =
      Format.asprintf "%a" Printer.pp_lval (host, NoOffset)
      |> String.split_on_char ' ' |> String.concat ""
    in
    call ~id:("eval_callee[" ^ name ^ "]." ^ id) ~family:"evaluation"
      ~request:(request "eval_callee" name) ~expect
      (fun () ->
         let callees = R.eval_callee host req in
         pretty_callees callees, Callees callees)
  | Exp e ->
    let name = exp_name e in
    let call ?(expect = expect) family f =
      call ~id:(family ^ "[" ^ name ^ "]." ^ id) ~family:"evaluation"
        ~request:(request family name) ~expect f
    in
    call "eval_exp" (fun () ->
        let ev = R.eval_exp e req in
        let v = R.as_cvalue_result ev and alarms = R.alarms ev in
        let singleton = R.is_singleton ev in
        Format.sprintf "%s; alarms: %s; singleton: %b"
          (pretty_result Cvalue.V.pretty v) (pretty_alarms alarms) singleton,
        Several [ Value v; Alarms alarms; Flag singleton ]);
    call "expr_deps" (fun () ->
        let zone = R.expr_deps e req in
        Format.asprintf "%a" Memory_zone.pretty zone, Zone (Ok zone));
    call "expr_dependencies" (fun () ->
        let deps = R.expr_dependencies e req in
        Format.asprintf "%a" Eva.Deps.pretty deps, Deps deps);
    match e.enode with
    | Lval lv ->
      call "eval_lval" (fun () ->
          let ev = R.eval_lval lv req in
          let v = R.as_cvalue_or_uninitialized ev in
          let initialized = R.is_initialized ev and alarms = R.alarms ev in
          Format.asprintf "%a; initialized: %b; alarms: %s"
            Cvalue.V_Or_Uninitialized.pretty v initialized
            (pretty_alarms alarms),
          Several [ Uninit v; Flag initialized; Alarms alarms ]);
      call "eval_address" (fun () ->
          let ev = R.eval_address lv req in
          let loc = R.as_location_result ev and zone = R.as_zone_result ev in
          let alarms = R.alarms ev in
          Format.sprintf "%s; zone: %s; alarms: %s"
            (pretty_result Locations.pretty loc)
            (pretty_result Memory_zone.pretty zone) (pretty_alarms alarms),
          Several [ Location loc; Zone zone; Alarms alarms ]);
      call "lval_deps" (fun () ->
          let zone = R.lval_deps lv req in
          Format.asprintf "%a" Memory_zone.pretty zone, Zone (Ok zone));
      (* The address of a variable without index reads no state. *)
      let rec indexed = function
        | NoOffset -> false
        | Field (_, offset) -> indexed offset
        | Index _ -> true
      in
      let expect =
        match lv with
        | Var _, offset when not (indexed offset) -> No_read
        | _ -> expect
      in
      call ~expect "address_deps" (fun () ->
          let zone = R.address_deps lv req in
          Format.asprintf "%a" Memory_zone.pretty zone, Zone (Ok zone))
    | _ -> ()

(* With the probes of a fixture, the requests at P under each selection:
   the stacks in the order of the answer, the subrequests, the model and
   the printed states, and each evaluation family of each probe. Then the
   same evaluations on a supplied Cvalue state, the callee of P, and the
   requests of disabled domains. *)
let selection_battery kf stmt stacks =
  match probes () with
  | [] -> ()
  | probes ->
    let names stacks = String.concat " " (List.map stack_name stacks) in
    let unreached = ref [] in
    call ~id:"stacks.unreached-P" ~family:"enumeration" ~expect:Resolver
      ~request:"Eva.Results.(at_start_of f |> callstacks) minus before P"
      (fun () ->
         let all = R.(at_start_of kf |> callstacks) in
         let reaches s = List.exists (Eva.Callstack.equal s) stacks in
         unreached :=
           List.filter (fun s -> not (reaches s)) all |> by_stack_name;
         names !unreached, Stacks !unreached);
    let first_exp =
      List.find_map (function Exp e -> Some e | Callee _ -> None) probes
    in
    List.iter (fun (sel, text, select) ->
        let req = select (R.before stmt) in
        let request = "before P" ^ (if text = "" then "" else " |> " ^ text) in
        let on id family f =
          call ~id:(id ^ "." ^ sel) ~family ~expect:Resolver
            ~request:("Eva.Results.(" ^ request ^ " |> " ^ id ^ ")") f
        in
        on "stacks" "selection" (fun () ->
            let stacks = R.callstacks req in
            names stacks, Stacks stacks);
        on "is_empty" "selection" (fun () ->
            let empty = R.is_empty req in
            string_of_bool empty, Flag empty);
        on "by_callstack" "selection" (fun () ->
            let subrequests = R.by_callstack req in
            let answer (stack, sub) =
              match first_exp with
              | None -> stack_name stack, Text
              | Some e ->
                let v = R.(eval_exp e sub |> as_cvalue_result) in
                stack_name stack ^ ": " ^ pretty_result Cvalue.V.pretty v,
                Value v
            in
            let answers = List.map answer subrequests in
            String.concat " " (List.map fst answers),
            Several (Stacks (List.map fst subrequests)
                     :: List.map snd answers));
        on "model" "selection" (fun () -> model req);
        on "print_states" "selection" (fun () ->
            R.print_states req
            |> List.map (fun (name, s) -> name ^ ": " ^ s)
            |> String.concat "\n",
            Text);
        List.iter (fun probe ->
            evaluate ~id:sel ~request ~expect:Resolver probe req)
          probes)
      (selections stacks !unreached);
    call ~id:"callee.P" ~family:"evaluation" ~expect:Resolver
      ~request:"Eva.Results.callee P"
      (fun () ->
         let callees = R.callee stmt in
         pretty_callees (Ok callees), Callees (Ok callees));
    (* A supplied state is the input of the evaluation, whatever the
       selection: the model of the first stack, with x = 7 if the fixture
       has a global x. *)
    let supplied = ref Cvalue.Model.top in
    begin match stacks with
      | [] -> ()
      | first :: _ ->
        call ~id:"supplied-state.source" ~family:"supplied-stack"
          ~expect:Resolver
          ~request:("Eva.Results.(before P |> in_callstack "
                    ^ stack_name first ^ " |> get_cvalue_model), x := 7")
          (fun () ->
             let m =
               R.(before stmt |> in_callstack first |> get_cvalue_model)
             in
             let m =
               match Globals.Vars.find_from_astinfo "x" Global with
               | x ->
                 Cvalue.Model.add_binding ~exact:true m
                   (Locations.of_varinfo x) (Cvalue.V.inject_int Z.(of_int 7))
               | exception Not_found -> m
             in
             supplied := m;
             Format.asprintf "%a" Cvalue.Model.pretty m, Model (Ok m));
        let states = [
          "supplied", "in_cvalue_state m", R.in_cvalue_state !supplied;
          "supplied-selected",
          "in_cvalue_state m |> in_callstack " ^ stack_name first
          ^ " |> filter_callstack (fun _ -> false)",
          R.in_cvalue_state !supplied |> R.in_callstack first
          |> R.filter_callstack (fun _ -> false);
        ] in
        List.iter (fun (id, request, req) ->
            call ~id:("model." ^ id) ~family:"supplied-state" ~expect:No_read
              ~request:("Eva.Results.(" ^ request ^ " |> get_cvalue_model)")
              (fun () -> model req);
            List.iter (fun probe ->
                evaluate ~id ~request ~expect:No_read probe req)
              probes)
          states
    end;
    (* Disabled domains keep their declared response, without reading. *)
    Option.iter (fun e ->
        call ~id:("equality_class[" ^ exp_name e ^ "]")
          ~family:"disabled-domain" ~expect:No_read
          ~request:"Eva.Results.(before P |> equality_class e)"
          (fun () ->
             let r = R.(before stmt |> equality_class e) in
             pretty_result (Pretty_utils.pp_list ~sep:", " Printer.pp_exp) r,
             Text);
        call ~id:("is_tainted[" ^ exp_name e ^ "]")
          ~family:"disabled-domain" ~expect:No_read
          ~request:"Eva.Results.(before P |> is_tainted (zone of e))"
          (fun () ->
             let r = R.(before stmt |> is_tainted Memory_zone.top) in
             pretty_result (fun fmt t ->
                 Format.pp_print_string fmt
                   (match t with
                    | R.Direct -> "direct" | Indirect -> "indirect"
                    | Untainted -> "untainted")) r,
             Text))
      first_exp;
    (* The order in which each enumeration answers, at the initial state,
       and at the start and the end of each defined function. *)
    let order id request req =
      call ~id:("order." ^ id) ~family:"enumeration" ~expect:Resolver
        ~request:("Eva.Results.(" ^ request ^ " |> callstacks)")
        (fun () ->
           let stacks = R.callstacks req in
           names stacks, Stacks stacks)
    in
    order "initial" "at_start" R.at_start;
    Globals.Functions.iter (fun kf ->
        if Kernel_function.is_definition kf then begin
          let name = Kernel_function.get_name kf in
          order ("start-of-" ^ name) ("at_start_of " ^ name) (R.at_start_of kf);
          order ("end-of-" ^ name) ("at_end_of " ^ name) (R.at_end_of kf)
        end)

let compute () =
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ();
  (* The final values are printed only when Eva is enabled. *)
  Eva.Parameters.Eva.set true;
  Eva.Analysis.compute ()

(* The analysis status and the callers of each function that a snapshot
   exports, as Eva.Eva_results.set_results installs them in the legacy
   tables: the payload itself, not a read of the restored results. *)
let export_calls_request () =
  call ~id:"export.calls" ~family:"snapshot" ~expect:Resolver
    ~request:"Eva.Eva_results.(pretty_calls (get_results ()))"
    (text (fun () ->
         Format.asprintf "%a" Eva.Eva_results.pretty_calls
           (Eva.Eva_results.get_results ())))

let battery kf stmt =
  let kf_name = Kernel_function.get_name kf in
  let names stacks = List.map stack_name stacks |> List.sort compare in
  (* The stacks used by the per-stack requests are the answer of this
     request, so that its reads are attributed. *)
  let stacks = ref [] in
  call ~id:"stacks.before-P" ~family:"enumeration" ~expect:Resolver
    ~request:"Eva.Results.(before P |> callstacks)"
    (text (fun () ->
         stacks := R.(before stmt |> callstacks);
         String.concat " " (names !stacks)));
  call ~id:"by_callstack.before-P" ~family:"enumeration" ~expect:Resolver
    ~request:"Eva.Results.(before P |> by_callstack)"
    (text (fun () ->
         String.concat " "
           (names (List.map fst R.(before stmt |> by_callstack)))));
  call ~id:("available." ^ kf_name) ~family:"availability" ~expect:Resolver
    ~request:"Eva.Results.are_available f"
    (text (fun () -> string_of_bool (R.are_available kf)));
  call ~id:("status." ^ kf_name) ~family:"availability" ~expect:Resolver
    ~request:"Eva.Analysis.status f"
    (text (fun () -> pretty_kf_status (Eva.Analysis.status kf)));
  (* Served by the reachability of the hit log, Hit_log.reach. *)
  call ~id:"reachable.P" ~family:"availability" ~expect:Resolver
    ~request:"Eva.Results.is_reachable P"
    (text (fun () -> string_of_bool (R.is_reachable stmt)));
  call ~id:"reachable-kinstr.P" ~family:"availability" ~expect:Resolver
    ~request:"Eva.Results.is_reachable_kinstr (Kstmt P)"
    (text (fun () -> string_of_bool (R.is_reachable_kinstr (Kstmt stmt))));
  let stacks = by_stack_name !stacks in
  List.iter (fun stack ->
      call ~id:("reachable-pos.P." ^ stack_name stack) ~family:"supplied-stack"
        ~expect:Resolver
        ~request:("Eva.Results.is_reachable_pos (P, " ^ stack_name stack ^ ")")
        (text (fun () ->
             string_of_bool
               (R.is_reachable_pos (Eva.Position.local stmt stack)))))
    stacks;
  (* The unfiltered request and the request on each supplied stack go
     through the resolver. *)
  let per_stack id request req f =
    call ~id ~family:"getter" ~request ~expect:Resolver (fun () -> f req);
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
  call ~id:("model.start-of-" ^ kf_name) ~family:"getter" ~expect:Resolver
    ~request:"Eva.Results.(at_start_of f |> get_cvalue_model)"
    (fun () -> model (R.at_start_of kf));
  call ~id:"model.initial" ~family:"getter" ~expect:Resolver
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
        ~expect:Resolver
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
     the analysis from the point states passed to its hook. *)
  List.iter (fun (stmt, kf) ->
      let name = Kernel_function.get_name kf in
      call ~id:(Format.sprintf "inout.call-%s@%d" name (line stmt))
        ~family:"inout" ~expect:No_read
        ~request:"Inout.get_precise_inout ~stmt f"
        (fun () ->
           let inout = Operational_inputs.get_internal_precise ~stmt kf in
           Format.asprintf "%a@\nLogic inputs:@ %a" Inout_type.pretty inout
             Memory_zone.pretty inout.over_logic_inputs,
           Inout inout))
    (call_sites ());
  (* The hit log rebuilds the exported states, and the callers and analysis
     status of each function. *)
  call ~id:"export.get_results" ~family:"alias" ~expect:Resolver
    ~request:"Eva.Eva_results.get_results ()"
    (text (fun () -> ignore (Eva.Eva_results.get_results ()); "exported"));
  export_calls_request ();
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
       pretty_result Cvalue.V.pretty result, Value result);
  selection_battery kf stmt stacks

(* {2 Reachability battery}

   Requests on every labelled statement and every function of the input
   files, on each callstack that the analysis creates: reached and
   unreachable points, bodies interpreted by a specification or a builtin,
   nontermination, and the results that are unavailable because they are
   pending, interrupted or not recorded. A call to [stop_analysis] stops
   the analysis; a call to [pending_probe] makes requests while it runs. *)

let stop_function = "stop_analysis"
let pending_function = "pending_probe"

(* The callstacks that the call hooks see during the analysis, latest
   first. They do not depend on the result store. *)
let seen_stacks = ref []

let stacks_of kf =
  List.filter (fun cs -> Kernel_function.equal (Eva.Callstack.top_kf cs) kf)
    !seen_stacks
  |> List.sort_uniq Eva.Callstack.compare
  |> by_stack_name

let labelled_statements () =
  let statements = ref [] in
  Globals.Functions.iter (fun kf ->
      if Kernel_function.is_definition kf then
        List.iter (fun stmt ->
            List.iter (function
                | Label (name, _, _) ->
                  statements := (name, kf, stmt) :: !statements
                | Case _ | Default _ -> ())
              stmt.labels)
          (Kernel_function.get_definition kf).sallstmts);
  List.sort (fun (_, _, s1) (_, _, s2) -> compare (line s1) (line s2))
    !statements

(* The functions declared in the input files, but the driver's own. *)
let input_functions () =
  let files = Kernel.Files.get () in
  let in_input kf =
    let file = Fileloc.path (Kernel_function.get_location kf) in
    List.exists (Filepath.equal file) files
  in
  let driver kf =
    List.mem (Kernel_function.get_name kf) [stop_function; pending_function]
  in
  Globals.Functions.fold (fun kf acc ->
      if in_input kf && not (driver kf) then kf :: acc else acc) []
  |> List.sort (fun a b ->
      compare (Kernel_function.get_name a) (Kernel_function.get_name b))

let reach_function kf =
  let name = Kernel_function.get_name kf in
  let id s = "fn." ^ name ^ "." ^ s in
  call ~id:(id "status") ~family:"availability" ~expect:Resolver
    ~request:("Eva.Analysis.status " ^ name)
    (text (fun () -> pretty_kf_status (Eva.Analysis.status kf)));
  call ~id:(id "available") ~family:"availability" ~expect:Resolver
    ~request:("Eva.Results.are_available " ^ name)
    (text (fun () -> string_of_bool (R.are_available kf)));
  call ~id:(id "stacks") ~family:"enumeration" ~expect:Resolver
    ~request:("Eva.Results.(at_start_of " ^ name ^ " |> callstacks)")
    (text (fun () ->
         R.(at_start_of kf |> callstacks) |> by_stack_name
         |> List.map stack_name |> String.concat " "));
  List.iter (fun stack ->
      call ~id:(id ("start." ^ stack_name stack)) ~family:"supplied-stack"
        ~expect:Resolver
        ~request:("Eva.Results.(at_start_of " ^ name ^ " |> in_callstack "
                  ^ stack_name stack ^ " |> get_cvalue_model)")
        (fun () -> model R.(at_start_of kf |> in_callstack stack)))
    (stacks_of kf)

(* The internal answers of the hit log, which the public requests convert:
   [none] when the hit log does not answer. They read no store. *)
let internal label stmt stack =
  let pretty pp = Format.asprintf "%a" (Pretty_utils.pp_opt ~none:"none" pp) in
  let classify point =
    pretty Eva.Hit_log.pretty_answer
      (Eva.Hit_log.classify ~callstack:stack point)
  in
  let before = classify (Before stmt) and after = classify (After stmt) in
  if not !quiet then begin
    log "internal %s.%s before=%s after=%s" label (stack_name stack) before
      after;
    emit (`Assoc [
        "kind", `String "internal";
        "label", `String label;
        "stack", `String (stack_name stack);
        "before", `String before;
        "after", `String after;
      ])
  end

(* The selections of a request at a statement of a function whose stacks,
   seen by the hooks, are [stacks]: unfiltered, every stack by a selector
   and by a predicate, each stack alone by a predicate, every stack but one
   by a selector and by a predicate, a selector with a predicate that
   rejects some or all of its stacks, and none, by an empty selector and by
   a predicate. *)
let reach_selections stacks =
  let equal = Eva.Callstack.equal in
  let list stacks =
    "[" ^ String.concat "; " (List.map stack_name stacks) ^ "]"
  in
  let only stack =
    "only:" ^ stack_name stack,
    "filter_callstack (fun cs -> cs = " ^ stack_name stack ^ ")",
    R.filter_callstack (equal stack)
  in
  let without stack =
    let others = List.filter (fun s -> not (equal s stack)) stacks in
    [ "selector-without:" ^ stack_name stack, "in_callstacks " ^ list others,
      R.in_callstacks others;
      "filter-without:" ^ stack_name stack,
      "filter_callstack (fun cs -> cs <> " ^ stack_name stack ^ ")",
      R.filter_callstack (fun cs -> not (equal cs stack)) ]
  in
  (* A selector and a predicate together. *)
  let rejected stack =
    "rejected:" ^ stack_name stack,
    "in_callstack " ^ stack_name stack
    ^ " |> filter_callstack (fun _ -> false)",
    (fun r -> R.filter_callstack (fun _ -> false) (R.in_callstack stack r))
  in
  let all_but stack =
    "selector-all-filter-without:" ^ stack_name stack,
    "in_callstacks " ^ list stacks ^ " |> filter_callstack (fun cs -> cs <> "
    ^ stack_name stack ^ ")",
    (fun r ->
       R.filter_callstack (fun cs -> not (equal cs stack))
         (R.in_callstacks stacks r))
  in
  (* Selectors whose stacks the predicate rejects: they are not part of
     the selection, whatever their state. *)
  let all_rejected =
    "selector-all-filter-none",
    "in_callstacks " ^ list stacks ^ " |> filter_callstack (fun _ -> false)",
    (fun r -> R.filter_callstack (fun _ -> false) (R.in_callstacks stacks r))
  in
  let others_only stack =
    let others = List.filter (fun s -> not (equal s stack)) stacks in
    "selector-without-filter-only:" ^ stack_name stack,
    "in_callstacks " ^ list others ^ " |> filter_callstack (fun cs -> cs = "
    ^ stack_name stack ^ ")",
    (fun r -> R.filter_callstack (equal stack) (R.in_callstacks others r))
  in
  let several = List.compare_length_with stacks 1 > 0 in
  [ "unfiltered", "", Fun.id;
    "selector-all", "in_callstacks " ^ list stacks, R.in_callstacks stacks;
    "filter-all", "filter_callstack (fun _ -> true)",
    R.filter_callstack (fun _ -> true) ]
  @ List.map only stacks
  @ (if several then List.concat_map without stacks else [])
  @ List.map rejected stacks
  @ (if several then List.map all_but stacks else [])
  @ (if several then all_rejected :: List.map others_only stacks else [])
  @ [ "selector-none", "in_callstacks []", R.in_callstacks [];
      "filter-none", "filter_callstack (fun _ -> false)",
      R.filter_callstack (fun _ -> false) ]

(* Under each selection of the state before a labelled statement: the
   stacks in the order of the answer, the subrequests of [by_callstack]
   with their models, the model and [is_empty]. [prefix] names the ids and
   [suffix] ends the requests. *)
let reach_selection ~prefix ~suffix label stmt (selection, text, select) =
  let req = select (R.before stmt) in
  let id s = prefix ^ label ^ "." ^ selection ^ "." ^ s in
  let request s =
    "Eva.Results.(before " ^ label ^ (if text = "" then "" else " |> " ^ text)
    ^ " |> " ^ s ^ ")" ^ suffix
  in
  let names stacks = String.concat " " (List.map stack_name stacks) in
  call ~id:(id "stacks") ~family:"selection" ~expect:Resolver
    ~request:(request "callstacks")
    (fun () -> let stacks = R.callstacks req in names stacks, Stacks stacks);
  call ~id:(id "by_callstack") ~family:"selection" ~expect:Resolver
    ~request:(request "by_callstack, get_cvalue_model of each")
    (fun () ->
       let subrequests = R.by_callstack req in
       let answer (stack, sub) =
         let result = R.get_cvalue_model_result sub in
         stack_name stack ^ ": "
         ^ pretty_result Cvalue.Model.pretty result,
         Model result
       in
       let answers = List.map answer subrequests in
       String.concat " | " (List.map fst answers),
       Several (Stacks (List.map fst subrequests) :: List.map snd answers));
  call ~id:(id "model") ~family:"selection" ~expect:Resolver
    ~request:(request "get_cvalue_model") (fun () -> model req);
  call ~id:(id "empty") ~family:"selection" ~expect:Resolver
    ~request:(request "is_empty")
    (fun () -> let empty = R.is_empty req in string_of_bool empty, Flag empty)

let reach_label (label, kf, stmt) =
  let id s = "reach." ^ label ^ "." ^ s in
  let request s = "Eva.Results.(" ^ s ^ ")" in
  call ~id:(id "stacks") ~family:"enumeration" ~expect:Resolver
    ~request:(request ("before " ^ label ^ " |> callstacks"))
    (text (fun () ->
         R.(before stmt |> callstacks) |> by_stack_name
         |> List.map stack_name |> String.concat " "));
  call ~id:(id "reachable") ~family:"reachability" ~expect:Resolver
    ~request:(request ("is_reachable " ^ label))
    (text (fun () -> string_of_bool (R.is_reachable stmt)));
  call ~id:(id "empty-before") ~family:"reachability" ~expect:Resolver
    ~request:(request ("before " ^ label ^ " |> is_empty"))
    (text (fun () -> string_of_bool (R.(before stmt |> is_empty))));
  call ~id:(id "empty-after") ~family:"reachability" ~expect:Resolver
    ~request:(request ("after " ^ label ^ " |> is_empty"))
    (text (fun () -> string_of_bool (R.(after stmt |> is_empty))));
  call ~id:(id "model-before") ~family:"getter" ~expect:Resolver
    ~request:(request ("before " ^ label ^ " |> get_cvalue_model"))
    (fun () -> model (R.before stmt));
  (* Requests on a disabled domain keep their declared error. *)
  call ~id:(id "equality") ~family:"disabled-domain" ~expect:No_read
    ~request:(request ("before " ^ label ^ " |> equality_class 0"))
    (text (fun () ->
         let zero = Cil.zero ~loc:(Cil_datatype.Stmt.loc stmt) in
         match R.(before stmt |> equality_class zero) with
         | Ok exps ->
           Format.asprintf "%a" (Pretty_utils.pp_list ~sep:", "
                                   Printer.pp_exp) exps
         | Error e -> pretty_error e));
  call ~id:(id "taint") ~family:"disabled-domain" ~expect:No_read
    ~request:(request ("before " ^ label ^ " |> is_tainted nothing"))
    (text (fun () ->
         match R.(before stmt |> is_tainted Memory_zone.bottom) with
         | Ok Direct -> "direct"
         | Ok Indirect -> "indirect"
         | Ok Untainted -> "untainted"
         | Error e -> pretty_error e));
  List.iter (fun stack ->
      internal label stmt stack;
      let on s = s ^ " |> in_callstack " ^ stack_name stack in
      let id s = id (s ^ "." ^ stack_name stack) in
      call ~id:(id "before") ~family:"supplied-stack" ~expect:Resolver
        ~request:(request (on ("before " ^ label) ^ " |> get_cvalue_model"))
        (fun () -> model R.(before stmt |> in_callstack stack));
      call ~id:(id "after") ~family:"supplied-stack" ~expect:Resolver
        ~request:(request (on ("after " ^ label) ^ " |> get_cvalue_model"))
        (fun () -> model R.(after stmt |> in_callstack stack));
      call ~id:(id "reachable-pos") ~family:"supplied-stack"
        ~expect:Resolver
        ~request:(request ("is_reachable_pos (" ^ label ^ ", "
                           ^ stack_name stack ^ ")"))
        (text (fun () ->
             string_of_bool
               (R.is_reachable_pos (Eva.Position.local stmt stack))));
      call ~id:(id "empty") ~family:"supplied-stack" ~expect:Resolver
        ~request:(request (on ("before " ^ label) ^ " |> is_empty"))
        (text (fun () ->
             string_of_bool R.(before stmt |> in_callstack stack |> is_empty))))
    (stacks_of kf);
  List.iter (reach_selection ~prefix:"select." ~suffix:"" label stmt)
    (reach_selections (stacks_of kf))

(* [restore_check] mode: the hit log declines every request after a
   restore. *)
let decline_after_restore = ref false

let restore_results results =
  Eva.Eva_results.set_results results;
  if !decline_after_restore then Eva.Hit_log.set_decline_control true

(* The results of the analysis, exported and restored: a restored
   analysis is computed, even an interrupted one. The availability of each
   function and the points of each labelled statement are then asked
   again. Last requests of the battery, since they replace the results. *)
let restore_requests () =
  call ~id:"restore" ~family:"snapshot" ~expect:Resolver
    ~request:"Eva.Eva_results.(set_results (get_results ()))"
    (text (fun () ->
         restore_results (Eva.Eva_results.get_results ());
         "restored"));
  let suffix = " after the restore" in
  computation_requests ~prefix:"restored." ~suffix;
  List.iter (fun kf ->
      let name = Kernel_function.get_name kf in
      let id s = "restored.fn." ^ name ^ "." ^ s in
      call ~id:(id "status") ~family:"availability" ~expect:Resolver
        ~request:("Eva.Analysis.status " ^ name ^ suffix)
        (text (fun () -> pretty_kf_status (Eva.Analysis.status kf)));
      call ~id:(id "available") ~family:"availability" ~expect:Resolver
        ~request:("Eva.Results.are_available " ^ name ^ suffix)
        (text (fun () -> string_of_bool (R.are_available kf))))
    (input_functions ());
  List.iter (fun (label, _kf, stmt) ->
      let id s = "restored.reach." ^ label ^ "." ^ s in
      let request s = "Eva.Results.(" ^ s ^ ")" ^ suffix in
      call ~id:(id "reachable") ~family:"reachability" ~expect:Resolver
        ~request:(request ("is_reachable " ^ label))
        (text (fun () -> string_of_bool (R.is_reachable stmt)));
      call ~id:(id "stacks") ~family:"enumeration" ~expect:Resolver
        ~request:(request ("before " ^ label ^ " |> callstacks"))
        (text (fun () ->
             R.(before stmt |> callstacks) |> by_stack_name
             |> List.map stack_name |> String.concat " "));
      call ~id:(id "model-before") ~family:"getter" ~expect:Resolver
        ~request:(request ("before " ^ label ^ " |> get_cvalue_model"))
        (fun () -> model (R.before stmt)))
    (labelled_statements ())

let reach_battery () =
  computation_requests ~prefix:"" ~suffix:"";
  List.iter reach_function (input_functions ());
  List.iter reach_label (labelled_statements ());
  (* A known top model, which is not an unavailable result. *)
  let top = R.in_cvalue_state Cvalue.Model.top in
  call ~id:"supplied-top.model" ~family:"supplied-state" ~expect:No_read
    ~request:"Eva.Results.(in_cvalue_state top |> get_cvalue_model)"
    (fun () -> model top);
  call ~id:"supplied-top.empty" ~family:"supplied-state" ~expect:No_read
    ~request:"Eva.Results.(in_cvalue_state top |> is_empty)"
    (text (fun () -> string_of_bool (R.is_empty top)));
  restore_requests ()

(* Requests made while the analysis runs, from the call hook of
   [pending_probe], on the stack of its caller. *)
let pending_requests callstack =
  let caller = Option.get (Eva.Callstack.pop callstack) in
  let caller_kf = Eva.Callstack.top_kf caller in
  List.iter (fun (label, kf, stmt) ->
      let id s = "pending." ^ label ^ "." ^ s in
      let request s = "Eva.Results.(" ^ s ^ ") during the analysis" in
      call ~id:(id "reachable") ~family:"reachability" ~expect:Resolver
        ~request:(request ("is_reachable " ^ label))
        (text (fun () -> string_of_bool (R.is_reachable stmt)));
      call ~id:(id "empty-before") ~family:"reachability" ~expect:Resolver
        ~request:(request ("before " ^ label ^ " |> is_empty"))
        (text (fun () -> string_of_bool (R.(before stmt |> is_empty))));
      call ~id:(id "stacks") ~family:"enumeration" ~expect:Resolver
        ~request:(request ("before " ^ label ^ " |> callstacks"))
        (text (fun () ->
             R.(before stmt |> callstacks) |> by_stack_name
             |> List.map stack_name |> String.concat " "));
      call ~id:(id "model-before") ~family:"getter" ~expect:Resolver
        ~request:(request ("before " ^ label ^ " |> get_cvalue_model"))
        (fun () -> model (R.before stmt));
      if Kernel_function.equal kf caller_kf then begin
        call ~id:(id ("before." ^ stack_name caller))
          ~family:"supplied-stack" ~expect:Resolver
          ~request:(request ("before " ^ label ^ " |> in_callstack "
                             ^ stack_name caller ^ " |> get_cvalue_model"))
          (fun () -> model R.(before stmt |> in_callstack caller));
        List.iter
          (reach_selection ~prefix:"pending.select."
             ~suffix:" during the analysis" label stmt)
          (reach_selections [ caller ])
      end)
    (labelled_statements ());
  let name = Kernel_function.get_name caller_kf in
  call ~id:("pending.fn." ^ name ^ ".status") ~family:"availability"
    ~expect:Resolver
    ~request:("Eva.Analysis.status " ^ name ^ " during the analysis")
    (text (fun () -> pretty_kf_status (Eva.Analysis.status caller_kf)));
  call ~id:("pending.fn." ^ name ^ ".available") ~family:"availability"
    ~expect:Resolver
    ~request:("Eva.Results.are_available " ^ name ^ " during the analysis")
    (text (fun () -> string_of_bool (R.are_available caller_kf)));
  computation_requests ~prefix:"pending." ~suffix:" during the analysis"

(* A program that defines the global [top_initial_state] starts from a top
   state: its points are reached with a known top model. *)
let top_initial_state () =
  let defined =
    Globals.Vars.fold
      (fun vi _ acc -> acc || vi.vname = "top_initial_state") false
  in
  if defined then begin
    log "initial state top";
    Eva.Eva_results.set_initial_state Cvalue.Model.top
  end

let reach_hooks = ref false

let register_reach_hooks () =
  if not !reach_hooks then begin
    reach_hooks := true;
    Eva.Cvalue_callbacks.register_at_start_hook (fun () -> seen_stacks := []);
    Eva.Cvalue_callbacks.register_call_hook (fun callstack kf _state _kind ->
        seen_stacks := callstack :: !seen_stacks;
        let name = Kernel_function.get_name kf in
        if name = stop_function then begin
          log "stop requested at %s" (stack_name callstack);
          Eva.Analysis.abort ()
        end
        else if name = pending_function then pending_requests callstack)
  end

(* {2 Plug-in readers and semantic reports}

   The minimal plug-ins read Eva's results through their own public
   interfaces: the call relations and the guard outcomes of Eva.Results,
   Callgraph, InOut's statement, expression, function and callwise
   effects, the variable filters that InOut registers in Server, and
   Eva's statuses, alarms and statistics. The battery asks each consumer
   once, in an order where each one computes its own answer: InOut and
   Callgraph memoize theirs. *)

(* The functions of the input files, defined or not. *)
let fixture_functions () = input_functions ()

let words = function [] -> "none" | list -> String.concat " " list

let pretty_kfs kfs = words (List.map Kernel_function.get_name kfs)

let pretty_callsites callsites =
  List.map (fun (kf, stmts) ->
      Kernel_function.get_name kf ^ "@"
      ^ String.concat "," (List.map (fun s -> string_of_int (line s)) stmts))
    callsites
  |> words

(* Call relations: whether each function is called, its callers, and the
   call statements in each caller. *)
let relation_requests () =
  List.iter (fun kf ->
      let name = Kernel_function.get_name kf in
      call ~id:("is_called." ^ name) ~family:"call-relations" ~expect:Resolver
        ~request:("Eva.Results.is_called " ^ name)
        (fun () ->
           let called = R.is_called kf in
           string_of_bool called, Flag called);
      call ~id:("callers." ^ name) ~family:"call-relations" ~expect:Resolver
        ~request:("Eva.Results.callers " ^ name)
        (text (fun () -> pretty_kfs (R.callers kf)));
      call ~id:("callsites." ^ name) ~family:"call-relations"
        ~expect:Resolver ~request:("Eva.Results.callsites " ^ name)
        (text (fun () -> pretty_callsites (R.callsites kf))))
    (fixture_functions ())

(* The statements of the defined functions of the input files. *)
let fixture_statements () =
  List.concat_map (fun kf ->
      if Kernel_function.is_definition kf
      then
        List.map (fun stmt -> kf, stmt)
          (Kernel_function.get_definition kf).sallstmts
      else [])
    (fixture_functions ())

let site kf stmt =
  Format.sprintf "%s@%d" (Kernel_function.get_name kf) (line stmt)

(* Guard outcomes: whether the analysis took each branch of each
   conditional. *)
let guard_requests () =
  List.iter (fun (kf, stmt) ->
      match stmt.skind with
      | If _ ->
        call ~id:("guard." ^ site kf stmt) ~family:"guards" ~expect:Resolver
          ~request:("Eva.Results.condition_truth_value " ^ site kf stmt)
          (fun () ->
             let then_, else_ = R.condition_truth_value stmt in
             Format.sprintf "then=%b else=%b" then_ else_,
             Several [ Flag then_; Flag else_ ])
      | _ -> ())
    (fixture_statements ())

(* Callgraph. Eva's final display computes the graph after the analysis;
   it is cleared so that the request computes it from Eva's results. *)
let callgraph_requests () =
  Project.clear
    ~selection:(State_selection.with_dependencies Callgraph.Cg.self) ();
  call ~id:"callgraph.edges" ~family:"callgraph" ~expect:Resolver
    ~request:"Callgraph.Cg.get ()"
    (text (fun () ->
         let module G = Callgraph.Cg.G in
         let g = Callgraph.Cg.get () in
         let edges =
           G.fold_edges_e (fun e acc ->
               Format.sprintf "%s->%s"
                 (site (G.E.src e) (G.E.label e))
                 (Kernel_function.get_name (G.E.dst e))
               :: acc)
             g []
         in
         let vertices =
           G.fold_vertex (fun kf acc -> Kernel_function.get_name kf :: acc)
             g []
         in
         Format.sprintf "vertices: %s; edges: %s"
           (words (List.sort compare vertices))
           (words (List.sort compare edges))));
  (* The graph is memoized. *)
  call ~id:"callgraph.rev_order" ~family:"callgraph" ~expect:No_read
    ~request:"Callgraph.Uses.iter_in_rev_order"
    (text (fun () ->
         let order = ref [] in
         Callgraph.Uses.iter_in_rev_order
           (fun kf -> order := Kernel_function.get_name kf :: !order);
         words (List.rev !order)))

(* InOut. Its function-wise results are memoized, and Eva's final display
   computes the outputs of the analyzed functions. The memos are cleared,
   and the functions are asked callees first, so that each request
   computes its own answer from Eva's results. The callwise results, which
   InOut records during the analysis, are kept. *)

(* The public interface of InOut, as Inout.ml defines it. The driver
   belongs to the library, which cannot depend on its main module. *)
module Inout = struct
  let expr_inputs = Inputs.expr
  let stmt_inputs = Inputs.statement
  let kf_inputs = Inputs.get_internal
  let kf_external_inputs = Inputs.get_external
  let stmt_outputs = Outputs.statement
  let kf_outputs = Outputs.get_internal
  let kf_external_outputs = Outputs.get_external
  let get_precise_inout = Operational_inputs.get_internal_precise
end

let pretty_zone zone = one_line (Format.asprintf "%a" Memory_zone.pretty zone)

let zone_answer zone = pretty_zone zone, Zone (Ok zone)

let inout_answer (inout : Inout_type.t) =
  let z = pretty_zone in
  Format.sprintf
    "inputs=[%s] inputs-if-termination=[%s] logic-inputs=[%s] \
     may-outputs=[%s] may-outputs-if-termination=[%s] sure-outputs=[%s]"
    (z inout.over_inputs) (z inout.over_inputs_if_termination)
    (z inout.over_logic_inputs) (z inout.over_outputs)
    (z inout.over_outputs_if_termination)
    (z inout.under_outputs_if_termination),
  Inout inout

(* The name of a statement: its function and line, numbered when several
   statements share the line. *)
let statement_name kf stmt =
  let stmts = (Kernel_function.get_definition kf).sallstmts in
  match List.filter (fun s -> line s = line stmt) stmts with
  | [ _ ] -> site kf stmt
  | same_line ->
    let rec index i = function
      | [] -> assert false
      | s :: tail ->
        if Cil_datatype.Stmt.equal s stmt then i else index (i + 1) tail
    in
    Format.sprintf "%s#%d" (site kf stmt) (index 1 same_line)

(* The functions of the input files, callees first. *)
let callees_first () =
  let fixture = fixture_functions () in
  let order = ref [] in
  Callgraph.Uses.iter_in_rev_order (fun kf ->
      if List.exists (Kernel_function.equal kf) fixture
      then order := kf :: !order);
  List.rev !order

(* The calls of the analysis, as the call hooks saw them: the callee, the
   caller and the call statement. *)
let analyzed_calls () =
  let compare_call (k1, _, s1) (k2, _, s2) =
    let c = Cil_datatype.Stmt.compare s1 s2 in
    if c <> 0 then c else Kernel_function.compare k1 k2
  in
  List.filter_map (fun cs ->
      Option.map (fun (stmt, caller) -> Eva.Callstack.top_kf cs, caller, stmt)
        (Eva.Callstack.top_caller cs))
    !seen_stacks
  |> List.sort_uniq compare_call

let reads_memory exp =
  let exception Found in
  let visitor = object
    inherit Visitor.frama_c_inplace
    method! vlval _ = raise Found
  end in
  try ignore (Visitor.visitFramacExpr visitor exp); false
  with Found -> true

let clear_inout_memos () =
  let memo analysis =
    State.get ("Inout.Cumulative_analysis.Memo(" ^ analysis ^ ")")
  in
  Project.clear
    ~selection:State_selection.(union
                                  (with_dependencies (memo "inputs"))
                                  (with_dependencies (memo "outputs")))
    ()

let inout_requests () =
  clear_inout_memos ();
  let called kf =
    List.exists (fun cs -> Kernel_function.equal (Eva.Callstack.top_kf cs) kf)
      !seen_stacks
  in
  List.iter (fun kf ->
      let name = Kernel_function.get_name kf in
      let zone reader request =
        call ~id:(Format.sprintf "inout.%s.%s" reader name)
          ~family:"inout-function" ~expect:Resolver
          ~request:(Format.sprintf "Inout.%s %s" reader name)
          (fun () -> zone_answer (request kf))
      in
      zone "kf_inputs" Inout.kf_inputs;
      zone "kf_external_inputs" Inout.kf_external_inputs;
      zone "kf_outputs" Inout.kf_outputs;
      zone "kf_external_outputs" Inout.kf_external_outputs;
      (* The callwise hooks of InOut compute the effects of each call during
         the analysis; the function-wise analysis computes those of the
         functions that are not called. *)
      call ~id:("inout.precise." ^ name) ~family:"inout-function"
        ~expect:(if called kf then No_read else Resolver)
        ~request:("Inout.get_precise_inout " ^ name)
        (fun () -> inout_answer (Inout.get_precise_inout kf)))
    (callees_first ());
  List.iter (fun (kf, caller, stmt) ->
      let name = statement_name caller stmt ^ "." ^ Kernel_function.get_name kf
      in
      call ~id:("inout.call." ^ name) ~family:"inout-callwise" ~expect:No_read
        ~request:("Inout.get_precise_inout ~stmt " ^ name)
        (fun () -> inout_answer (Inout.get_precise_inout ~stmt kf)))
    (analyzed_calls ());
  List.iter (fun (kf, stmt) ->
      let name = statement_name kf stmt in
      let request reader answer =
        call ~id:(Format.sprintf "inout.%s.%s" reader name)
          ~family:("inout-" ^ if reader = "expr_inputs" then "expression"
                   else "statement")
          ~expect:Resolver ~request:(Format.sprintf "Inout.%s %s" reader name)
          answer
      in
      begin match stmt.skind with
        | Instr _ ->
          request "stmt_inputs"
            (fun () -> zone_answer (Inout.stmt_inputs stmt));
          request "stmt_outputs"
            (fun () -> zone_answer (Inout.stmt_outputs stmt))
        | _ -> ()
      end;
      match stmt.skind with
      | Instr (Set (_, exp, _)) | Return (Some exp, _) when reads_memory exp ->
        request "expr_inputs"
          (fun () -> zone_answer (Inout.expr_inputs stmt exp))
      | _ -> ())
    (fixture_statements ())

(* Server: the variable filters that InOut registers, as the array of
   global variables gives them. Each filter is enabled once Eva has
   computed its results; it then reads InOut's effects of the entry point,
   which the InOut requests have memoized. *)
let server_request name json =
  match Server.Main.find name with
  | None -> Inout_parameters.abort "server request %s not registered" name
  | Some _ -> Server.Main.exec name json

let member key = function
  | `Assoc fields -> Option.value ~default:`Null (List.assoc_opt key fields)
  | _ -> `Null

(* The rows of a Server array, fully reloaded. *)
let server_rows package array =
  let request kind = Format.sprintf "%s.%s%s" package kind array in
  ignore (server_request (request "reload") `Null);
  match member "updated" (server_request (request "fetch") (`Int 10_000)) with
  | `List rows -> rows
  | _ -> []

let server_filter_requests () =
  let filters row =
    let value name =
      match member "filters" row with
      | `List filters ->
        List.find_map (function
            | `List [ `String n; `Bool b ] when n = name -> Some b
            | _ -> None)
          filters
      | _ -> None
    in
    let effects =
      List.filter_map (fun (name, label) ->
          match value name with
          | Some true -> Some label
          | Some false -> None
          | None -> Some (label ^ "-disabled"))
        [ "read", "read"; "written", "written" ]
    in
    if effects = [] then "none" else String.concat "," effects
  in
  call ~id:"server.globals.filters" ~family:"server-filters" ~expect:Resolver
    ~request:"kernel.ast.reloadGlobals; kernel.ast.fetchGlobals"
    (text (fun () ->
         List.filter_map (fun row ->
             match member "name" row, member "stringLiteral" row with
             | `String name, `Bool false -> Some (name ^ ":" ^ filters row)
             | _ -> None)
           (server_rows "kernel.ast" "Globals")
         |> List.sort compare |> String.concat " "))

(* Statuses, alarms and statistics. Eva emits them from its results during
   the analysis and after it; they are stored apart from its results, and
   reading them reads neither store. *)

let in_fixture_file loc =
  List.exists (Filepath.equal (Fileloc.path loc)) (Kernel.Files.get ())

(* The status that Eva emits on each property of the input files, and the
   consolidated status. *)
let status_requests () =
  let properties =
    Property_status.fold (fun ip acc ->
        if in_fixture_file (Property.location ip)
        then (one_line (Format.asprintf "%a" Property.pretty ip), ip) :: acc
        else acc)
      []
    |> List.sort (fun (k1, ip1) (k2, ip2) ->
        let c =
          compare (Fileloc.line (Property.location ip1))
            (Fileloc.line (Property.location ip2))
        in
        if c <> 0 then c else compare k1 k2)
  in
  let eva = Emitter.get_name Eva.Analysis.emitter in
  let rec index line i = function
    | [] -> []
    | (key, ip) :: tail ->
      let l = Fileloc.line (Property.location ip) in
      let i = if l = line then i + 1 else 1 in
      (Format.sprintf "status.L%d#%d" l i, key, ip) :: index l i tail
  in
  List.iter (fun (id, key, ip) ->
      call ~id ~family:"statuses" ~expect:No_read
        ~request:("Property_status " ^ key)
        (text (fun () ->
             let emitted =
               Property_status.fold_on_statuses (fun e status acc ->
                   if Emitter.Usable_emitter.get_name e.emitter = eva
                   then
                     Format.asprintf "%a" Property_status.Emitted_status.pretty
                       status
                     :: acc
                   else acc)
                 ip []
             in
             Format.asprintf "%s: eva=%s consolidated=%a" key (words emitted)
               Property_status.Feedback.pretty
               (Property_status.Feedback.get ip))))
    (index 0 0 properties);
  (* Ivette's view of the properties, with the alarms. *)
  call ~id:"server.properties" ~family:"statuses" ~expect:No_read
    ~request:"kernel.properties.reloadStatus; kernel.properties.fetchStatus"
    (text (fun () ->
         let field key row =
           match member key row with
           | `String s -> s
           | `Int n -> string_of_int n
           | `Null -> "-"
           | json -> Yojson.Basic.to_string json
         in
         let base =
           List.map (fun f -> Filename.basename (Filepath.to_string f))
             (Kernel.Files.get ())
         in
         List.filter_map (fun row ->
             let source = member "source" row in
             if List.mem (field "base" source) base then
               Some (Format.sprintf "L%s %s %s %s"
                       (field "line" source) (field "kind" row)
                       (field "alarm" row) (field "status" row))
             else None)
           (server_rows "kernel.properties" "Status")
         |> List.sort compare |> String.concat " | "))

(* The statistics that Eva computes from its results; the statistics of the
   execution, which other runs need not share, are recorded apart. *)
let statistics_requests () =
  let open Eva.Statistics in
  call ~id:"statistics.semantic" ~family:"statistics" ~expect:No_read
    ~request:"Eva.Statistics.get alarm_count, stmt_coverage, fun_coverage"
    (text (fun () ->
         Format.sprintf "alarm-count=%d stmt-coverage=%.6f fun-coverage=%.6f"
           (get alarm_count ()) (get stmt_coverage ()) (get fun_coverage ())));
  if not !quiet then begin
    let stmts = List.map snd (fixture_statements ()) in
    let kfs = fixture_functions () in
    let sum stat elements =
      `Int (List.fold_left (fun acc x -> acc + get stat x) 0 elements)
    in
    let execution = [
      "memory-usage", `Int (get memory_usage ());
      "analysis-time", `Float (get analysis_duration ());
      "iterations", sum iterations stmts;
      "memexec-hits", sum memexec_hits kfs;
      "memexec-misses", sum memexec_misses kfs;
      "max-widenings", sum max_widenings stmts;
      "max-unrolling", sum max_unrolling stmts;
      "partitioning-index-hits", `Int (get partitioning_index_hits ());
      "partitioning-index-misses", `Int (get partitioning_index_misses ());
    ] in
    log "execution-statistics %s" (String.concat " " (List.map fst execution));
    emit (`Assoc [
        "kind", `String "execution-statistics";
        "values", `Assoc execution;
      ])
  end

(* The analysis status of each function, as Eva.Analysis.status answers. *)
let statuses () =
  List.map (fun kf ->
      Format.asprintf "%a: %s" Kernel_function.pretty kf
        (pretty_kf_status (Eva.Analysis.status kf)))
    (fixture_functions ())
  |> String.concat "\n"

(* A snapshot of the results, restored after an intervening analysis. The
   exported payload is compared first. The snapshot is then taken, and a
   new analysis interprets the first function called by main by its
   specification: its statuses must differ. Restoring the snapshot must
   give back the statuses of the first analysis, read under the same guard
   as the rest of the run. The intervening analysis also runs under that
   guard. Last requests of the battery, since they replace the results. *)
let snapshot_requests () =
  export_calls_request ();
  let snapshot = ref None and first = ref "" in
  call ~id:"snapshot.statuses" ~family:"snapshot" ~expect:Resolver
    ~request:"Eva.Analysis.status of each function, then \
              Eva.Eva_results.get_results ()"
    (text (fun () ->
         first := statuses ();
         snapshot := Some (Eva.Eva_results.get_results ());
         !first));
  let spec =
    List.find_map (fun (stmt, kf) ->
        let caller = Kernel_function.find_englobing_kf stmt in
        if Kernel_function.equal caller (fst (Globals.entry_point ()))
        then Some kf else None)
      (call_sites ())
  in
  Option.iter (fun spec ->
      let name = Kernel_function.get_name spec in
      call ~id:"snapshot.intervening" ~family:"snapshot" ~expect:Resolver
        ~request:("Eva.Analysis.status of each function after a new analysis \
                   with -eva-use-spec " ^ name)
        (text (fun () ->
             let use_spec = Eva.Parameters.UseSpec.get () in
             (* The specification has no assigns clause: the warning would
                be a deferred error at the end of the run. No analysis
                follows this one. *)
             Dynamic.Parameter.String.set "-eva-warn-key"
               "assigns:missing=inactive";
             Eva.Parameters.UseSpec.set (Kernel_function.Set.add spec use_spec);
             compute ();
             let intervening = statuses () in
             Eva.Parameters.UseSpec.set use_spec;
             Printf.sprintf "differs=%b\n%s" (intervening <> !first)
               intervening)))
    spec;
  call ~id:"export.statuses" ~family:"snapshot" ~expect:Resolver
    ~request:"Eva.Eva_results.set_results (the snapshot), then \
              Eva.Analysis.status of each function"
    (text (fun () ->
         Option.iter restore_results !snapshot;
         statuses ()))

(* [snapshot] adds the snapshot requests, which run a new analysis. *)
let plugin_battery ~snapshot =
  (* Server's filters and Callgraph ask whether the results are computed
     before reading them. *)
  computation_requests ~prefix:"" ~suffix:"";
  relation_requests ();
  guard_requests ();
  callgraph_requests ();
  inout_requests ();
  server_filter_requests ();
  status_requests ();
  statistics_requests ();
  if snapshot then snapshot_requests ()

(* {2 Header} *)

let guard_name : Guard.mode -> string = function
  | Off -> "off"
  | Record -> "record"
  | Trap phases when phases = Guard.all_phases -> "trap:all"
  | Trap phases ->
    "trap:" ^ String.concat "," (List.map Guard.phase_name phases)

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
  let guard = guard_name (Guard.mode ()) in
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
      (* The optional server API of Eva, which the readers do not use. *)
      "eva_server_api",
      `Bool (Option.is_some (Server.Main.find "plugins.eva.ast.getCallers"));
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
     states passed to its hook makes no read of its own. *)
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

(* The first statement of the entry point. *)
let entry_statement () =
  let main, _ = Globals.entry_point () in
  Kernel_function.find_first_stmt main

(* Tail probe: once the battery has run, still under the trap, the results
   are cleared, so that the hit log no longer describes them, and one point
   request is made. It reads the legacy store, which must abort the run. *)
let tail_probe () =
  log "tail-probe logged=%d trapped=%d" (List.length (Guard.reads ()))
    (Guard.trapped_count ());
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ();
  log "tail-probe Eva.Results.(before <first statement of main> \
       |> get_cvalue_model) on cleared results";
  ignore R.(before (entry_statement ()) |> get_cvalue_model);
  log "tail-probe not trapped"

(* The reference is fresh-only and reads the legacy store alone. *)
let legacy_reference () =
  Eva.Parameters.Memexec.set false;
  Eva.Parameters.HitLog.set false;
  Guard.arm Off

(* The reads and the resolutions of each phase, with the number of entries
   of the phase while the guard was armed, and the resolutions of each
   reader that registers results during the analysis. *)
let scopes () =
  let reads = Guard.reads () and resolutions = Guard.resolutions () in
  let count phase list field =
    List.length (List.filter (fun x -> field x = phase) list)
  in
  let registration = [
    "Eva.Engine.register_state"; "Eva.Function_calls.register_analysis_target";
    "Eva.Iterator.record_fireable" ] in
  List.iter (fun (phase, entries) ->
      let n_reads = count phase reads (fun (r : Guard.read) -> r.phase)
      and n_resolutions =
        count phase resolutions (fun (r : Guard.resolution) -> r.resolved_phase)
      in
      let by_reader label =
        List.length (List.filter (fun (r : Guard.resolution) ->
            r.resolved_phase = phase && List.mem label r.resolved_readers)
            resolutions)
      in
      let registrations = List.map (fun l -> l, by_reader l) registration in
      log "scope %s entries=%d reads=%d resolutions=%d registrations=%s"
        (Guard.phase_name phase) entries n_reads n_resolutions
        (String.concat "," (List.map (fun (l, n) ->
             Printf.sprintf "%s:%d" l n) registrations));
      emit (`Assoc [
          "kind", `String "scope";
          "phase", `String (Guard.phase_name phase);
          "entries", `Int entries;
          "reads", `Int n_reads;
          "resolutions", `Int n_resolutions;
          "registrations",
          `Assoc (List.map (fun (l, n) -> l, `Int n) registrations);
        ]))
    (Guard.phase_entries ())

let accounting () =
  let logged = List.length (Guard.reads ()) in
  log "accounting logged=%d attributed=%d" logged !attributed;
  emit (`Assoc [
      "kind", `String "accounting";
      "logged", `Int logged;
      "attributed", `Int !attributed;
    ])

(* The state of the guard at the end of the run: the modes armed since the
   start of the process, the first trapped read and the number of reads.
   The zero-read gate passes when the guard was armed once, with the
   continuous trap, and when no read was logged or trapped. *)
let gate () =
  let arms = List.map guard_name (Guard.arm_history ()) in
  let logged = List.length (Guard.reads ()) in
  let trapped = Guard.trapped () in
  let passes =
    arms = [ "trap:all" ] && logged = 0 && Option.is_none trapped
    && Guard.trapped_count () = 0
  in
  log "gate arms=%s final=%s logged=%d trapped=%d passes=%b"
    (String.concat ">" arms) (guard_name (Guard.mode ())) logged
    (Guard.trapped_count ()) passes;
  emit (`Assoc [
      "kind", `String "gate";
      "arms", `List (List.map (fun a -> `String a) arms);
      "final", `String (guard_name (Guard.mode ()));
      "logged", `Int logged;
      "trapped", Option.fold ~none:`Null ~some:json_of_read trapped;
      "trapped_count", `Int (Guard.trapped_count ());
      "passes", `Bool passes;
    ]);
  passes

(* Native mode: the fresh-only reference and the candidate run in the same
   process, on the same AST, so that their models are compared with the
   native equality of Cvalue, and InOut's callwise results with the
   equality of their zones. *)
let native (run_battery : snapshot:bool -> unit) =
  quiet := true;
  legacy_reference ();
  (* The guard does not change the answers: record the reads of the
     reference too, to show that it took the legacy path. *)
  Guard.arm Record;
  compute ();
  (* The intervening analysis of the snapshot requests makes Eva generate
     an assigns clause for the function it uses by its specification: the
     candidate half would see the new properties. These requests are only
     compared across processes. *)
  run_battery ~snapshot:false;
  let reference = List.rev !answers in
  answers := [];
  Eva.Parameters.HitLog.set true;
  Guard.clear ();
  (* The candidate runs under the continuous trap. *)
  Guard.arm (Trap Guard.all_phases);
  compute ();
  run_battery ~snapshot:true;
  let candidate = List.rev !answers in
  let find id = List.find_opt (fun a -> a.id = id) candidate in
  let compared = ref 0 and differing = ref 0 in
  List.iter (fun expected ->
      match find expected.id with
      | None ->
        log "native %s missing" expected.id;
        incr differing
      | Some observed ->
        let equal = native_equal expected.native observed.native in
        Option.iter (fun equal ->
            incr compared;
            if not equal then incr differing;
            log "native %s equal=%b reference-reads=%d reference-resolved=%d \
                 legacy-reads=%d resolved=%d" expected.id equal
              (List.length expected.reads) (List.length expected.resolutions)
              (List.length observed.reads) (List.length observed.resolutions))
          equal;
        (* Answers without a native comparison are recorded too, with the
           path that served them; equal is then null. *)
        emit (`Assoc [
            "kind", `String "native";
            "id", `String expected.id;
            "equal", Option.fold ~none:`Null ~some:(fun b -> `Bool b) equal;
            "text_equal", `Bool (String.equal expected.text observed.text);
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
    let kind, mode = parse_mode name in
    let run_battery ~snapshot =
      match kind with
      | Point_battery ->
        let kf, stmt = target () in
        battery kf stmt
      | Reach_battery -> reach_battery ()
      | Plugin_battery -> plugin_battery ~snapshot
    in
    if kind = Reach_battery then begin
      register_reach_hooks ();
      top_initial_state ()
    end;
    (* The call hooks give the calls of the analysis without reading its
       results. *)
    if kind = Plugin_battery then register_reach_hooks ();
    begin match Inout_parameters.QueryAcceptanceOutput.get () with
      | "" -> ()
      | file -> output := Some (open_out file)
    end;
    Guard.clear ();
    (* The guard is armed once, before the analysis starts. *)
    begin match mode with
      | Reference -> legacy_reference ()
      | Candidate | Tail_probe -> Guard.arm (Trap Guard.all_phases)
      | Record_reads | Native -> Guard.arm Record
      | Wrong_producer ->
        Eva.Hit_log.set_wrong_producer_control true;
        Guard.arm Record
      | Perturb_calls ->
        Eva.Hit_log.set_calls_perturbation_control true;
        Guard.arm Record
      | Store_check -> Guard.arm Record
      | Restore_check ->
        decline_after_restore := true;
        Guard.arm Record
      | Trap phase -> Guard.arm (Trap [phase])
    end;
    header name;
    begin match mode with
      | Native -> native run_battery
      | _ ->
        compute ();
        match mode with
        | Trap Request -> control (snd (target ()))
        | Trap phase ->
          log "control not trapped in phase %s" (Guard.phase_name phase)
        | Reference | Candidate | Record_reads | Wrong_producer | Native
        | Tail_probe | Store_check | Perturb_calls | Restore_check ->
          if mode = Store_check then Eva.Hit_log.set_decline_control true;
          execution ();
          run_battery ~snapshot:true;
          (* Every logged read must belong to the execution or to one
             call. *)
          accounting ();
          scopes ();
          match mode with
          | Candidate ->
            if not (gate ()) then
              Inout_parameters.abort "the zero-read gate failed"
          | Tail_probe -> ignore (gate ()); tail_probe ()
          | _ -> ()
    end;
    Option.iter close_out !output

let () = Boot.Main.extend run
