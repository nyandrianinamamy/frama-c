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

(* The requests made after the analysis: the battery around the statement
   labelled P, or the reachability battery on every labelled statement
   ([reach-] modes). *)
type battery = Point_battery | Reach_battery

let rec parse_mode name =
  let reach = "reach-" in
  if String.starts_with ~prefix:reach name then
    let len = String.length reach in
    match parse_mode (String.sub name len (String.length name - len)) with
    | Point_battery, (Reference | Candidate | Native as mode) ->
      Reach_battery, mode
    | _ ->
      Inout_parameters.abort "unknown mode %S for %s" name
        Inout_parameters.QueryAcceptance.option_name
  else
    let mode =
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
  call ~id:("available." ^ kf_name) ~family:"availability" ~expect:Legacy
    ~request:"Eva.Results.are_available f"
    (text (fun () -> string_of_bool (R.are_available kf)));
  call ~id:("status." ^ kf_name) ~family:"availability" ~expect:Legacy
    ~request:"Eva.Analysis.status f"
    (text (fun () -> pretty_kf_status (Eva.Analysis.status kf)));
  (* Served by the reachability of the hit log, Hit_log.reach. *)
  call ~id:"reachable.P" ~family:"availability" ~expect:Resolver
    ~request:"Eva.Results.is_reachable P"
    (text (fun () -> string_of_bool (R.is_reachable stmt)));
  let stacks = by_stack_name !stacks in
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
  call ~id:(id "status") ~family:"availability" ~expect:Legacy
    ~request:("Eva.Analysis.status " ^ name)
    (text (fun () -> pretty_kf_status (Eva.Analysis.status kf)));
  call ~id:(id "available") ~family:"availability" ~expect:Legacy
    ~request:("Eva.Results.are_available " ^ name)
    (text (fun () -> string_of_bool (R.are_available kf)));
  call ~id:(id "stacks") ~family:"enumeration" ~expect:Legacy
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

let reach_label (label, kf, stmt) =
  let id s = "reach." ^ label ^ "." ^ s in
  let request s = "Eva.Results.(" ^ s ^ ")" in
  call ~id:(id "stacks") ~family:"enumeration" ~expect:Legacy
    ~request:(request ("before " ^ label ^ " |> callstacks"))
    (text (fun () ->
         R.(before stmt |> callstacks) |> by_stack_name
         |> List.map stack_name |> String.concat " "));
  call ~id:(id "reachable") ~family:"reachability" ~expect:Legacy
    ~request:(request ("is_reachable " ^ label))
    (text (fun () -> string_of_bool (R.is_reachable stmt)));
  call ~id:(id "empty-before") ~family:"reachability" ~expect:Legacy
    ~request:(request ("before " ^ label ^ " |> is_empty"))
    (text (fun () -> string_of_bool (R.(before stmt |> is_empty))));
  call ~id:(id "empty-after") ~family:"reachability" ~expect:Legacy
    ~request:(request ("after " ^ label ^ " |> is_empty"))
    (text (fun () -> string_of_bool (R.(after stmt |> is_empty))));
  call ~id:(id "model-before") ~family:"getter" ~expect:Legacy
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
    (stacks_of kf)

let reach_battery () =
  List.iter reach_function (input_functions ());
  List.iter reach_label (labelled_statements ());
  (* A known top model, which is not an unavailable result. *)
  let top = R.in_cvalue_state Cvalue.Model.top in
  call ~id:"supplied-top.model" ~family:"supplied-state" ~expect:No_read
    ~request:"Eva.Results.(in_cvalue_state top |> get_cvalue_model)"
    (fun () -> model top);
  call ~id:"supplied-top.empty" ~family:"supplied-state" ~expect:No_read
    ~request:"Eva.Results.(in_cvalue_state top |> is_empty)"
    (text (fun () -> string_of_bool (R.is_empty top)))

(* Requests made while the analysis runs, from the call hook of
   [pending_probe], on the stack of its caller. *)
let pending_requests callstack =
  let caller = Option.get (Eva.Callstack.pop callstack) in
  let caller_kf = Eva.Callstack.top_kf caller in
  List.iter (fun (label, kf, stmt) ->
      let id s = "pending." ^ label ^ "." ^ s in
      let request s = "Eva.Results.(" ^ s ^ ") during the analysis" in
      call ~id:(id "reachable") ~family:"reachability" ~expect:Legacy
        ~request:(request ("is_reachable " ^ label))
        (text (fun () -> string_of_bool (R.is_reachable stmt)));
      call ~id:(id "empty-before") ~family:"reachability" ~expect:Legacy
        ~request:(request ("before " ^ label ^ " |> is_empty"))
        (text (fun () -> string_of_bool (R.(before stmt |> is_empty))));
      call ~id:(id "stacks") ~family:"enumeration" ~expect:Legacy
        ~request:(request ("before " ^ label ^ " |> callstacks"))
        (text (fun () ->
             R.(before stmt |> callstacks) |> by_stack_name
             |> List.map stack_name |> String.concat " "));
      call ~id:(id "model-before") ~family:"getter" ~expect:Legacy
        ~request:(request ("before " ^ label ^ " |> get_cvalue_model"))
        (fun () -> model (R.before stmt));
      if Kernel_function.equal kf caller_kf then
        call ~id:(id ("before." ^ stack_name caller))
          ~family:"supplied-stack" ~expect:Resolver
          ~request:(request ("before " ^ label ^ " |> in_callstack "
                             ^ stack_name caller ^ " |> get_cvalue_model"))
          (fun () -> model R.(before stmt |> in_callstack caller)))
    (labelled_statements ());
  let name = Kernel_function.get_name caller_kf in
  call ~id:("pending.fn." ^ name ^ ".status") ~family:"availability"
    ~expect:Legacy
    ~request:("Eva.Analysis.status " ^ name ^ " during the analysis")
    (text (fun () -> pretty_kf_status (Eva.Analysis.status caller_kf)));
  call ~id:("pending.fn." ^ name ^ ".available") ~family:"availability"
    ~expect:Legacy
    ~request:("Eva.Results.are_available " ^ name ^ " during the analysis")
    (text (fun () -> string_of_bool (R.are_available caller_kf)))

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
   native equality of Cvalue, and InOut's callwise results with the
   equality of their zones. *)
let native run_battery =
  quiet := true;
  legacy_reference ();
  (* The guard does not change the answers: record the reads of the
     reference too, to show that it took the legacy path. *)
  Guard.arm Record;
  compute ();
  run_battery ();
  let reference = List.rev !answers in
  answers := [];
  Eva.Parameters.HitLog.set true;
  Guard.clear ();
  Guard.arm Record;
  compute ();
  run_battery ();
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
    let run_battery () =
      match kind with
      | Point_battery ->
        let kf, stmt = target () in
        battery kf stmt
      | Reach_battery -> reach_battery ()
    in
    if kind = Reach_battery then begin
      register_reach_hooks ();
      top_initial_state ()
    end;
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
      | Native -> native run_battery
      | _ ->
        compute ();
        match mode with
        | Trap Request -> control (snd (target ()))
        | Trap phase ->
          log "control not trapped in phase %s" (Guard.phase_name phase)
        | Reference | Candidate | Wrong_producer | Native ->
          execution ();
          run_battery ();
          (* Every logged read must belong to the execution or to one
             call. *)
          accounting ()
    end;
    Option.iter close_out !output

let () = Boot.Main.extend run
