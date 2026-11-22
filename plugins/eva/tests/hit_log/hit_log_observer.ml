(* Observer of the tests of option -eva-hit-log.

   The current project is analysed with the options of the test, which set
   -eva-hit-log. Two copies of it, made before, are analysed without
   recording: the reference, without memexec, and a run with memexec. After
   the analyses, the observer asks Eva.Results, in each project, for the
   callstacks that reach the start of each function and the points before and
   after each statement, then for the state at each of these points: joined
   over the callstacks, through a filter that rejects one of the callstacks
   when there are several, and for each callstack that reaches the point in
   one of the three projects.

   It prints:
   - the calls of the analysis with -eva-hit-log, with the cache entry they
     compute or use;
   - the callstacks that reach the start of a function in the current project
     and are not those of a call of the analysis: the calls below a hit,
     whose body did not run;
   - the states at the labelled statements, and those of the reference when
     they differ;
   - for each hit on another callstack than the analysed call of its cache
     entry, the variables whose values differ between the two callstacks, at
     the points of the function where both answers are available;
   - the verdict on the initial state, then each answer that is not equal to
     the answer to the same request in the reference, with one of these
     verdicts:
     "covers": the answer includes the reference and is larger;
     "more precise": the answer is included in the reference and smaller;
     "OMITS": the answer does not include the reference;
     "unavailable": the answer is top, as for a function without results.
     A verdict is followed by "as with memexec" when the answer equals that of
     the run with memexec and without recording: the difference comes from
     the analysis with memexec, not from the answers served from the hit log.
     "unavailable" is followed by "as in the reference" when the reference is
     top as well;
   - the number of filtered requests that reject a callstack;
   - whether each request made in the current project is reported by
     Eva.Legacy_read_trap, once and with its description, and the reads of
     the legacy store that it reports;
   - the requests made after the iteration, by the passes that Eva runs and
     by the hooks run when Eva has results, in the run with memexec and in
     the run with -eva-hit-log: their number by pass, the reads of the legacy
     store within them and outside any request, as reported by
     Eva.Legacy_read_trap, which is on during these two analyses; and the
     requests made on the callstacks below a hit;
   - the outputs of these passes, against the run without memexec: the
     statuses of the properties, the alarms, the statement and function
     coverage and the number of alarms of the summary, and the messages they
     print, if any.
     When the analysis with -eva-hit-log has no result, as when it is refused,
     no request is made.

   When the environment variable HIT_LOG_OBSERVER_SUMMARY names a file, the
   observer also writes there a summary of its run, for dev/hit-log-suite.py,
   which runs it over the tests of Eva: one record per line, with fields
   separated by tabs. In this mode, it also requests the start of the
   functions without a body that are called in the reference, and it gives
   for each unavailable answer the case of the closed list of #87 that the
   run shows, if any. It stops if the analysis of the current project is
   computed before it starts. What it prints is otherwise unchanged. *)

open Eva

(* ----- Summary ----------------------------------------------------------- *)

let summary =
  match Sys.getenv_opt "HIT_LOG_OBSERVER_SUMMARY" with
  | None | Some "" -> None
  | Some file -> Some (open_out file)

let suite = Option.is_some summary

(* Writes one record of the summary, flushed at once, so that the record of
   a phase is kept if the run is stopped during that phase. *)
let record fields =
  Option.iter
    (fun channel ->
       let clean = String.map (function '\t' | '\n' | '\r' -> ' ' | c -> c) in
       output_string channel (String.concat "\t" (List.map clean fields));
       output_char channel '\n';
       flush channel)
    summary

(* ----- Calls of the analysis --------------------------------------------- *)

type call_kind = Analysed of int | Hit of int | Other of string

let string_of_callstack = Format.asprintf "%a" Legacy_read_trap.pretty_callstack

(* A callstack in a form that is rebuilt in another project: the functions by
   name, the call statements by number. *)
type portable = {
  thread: int;
  entry: string;
  calls: (string * int) list;
}

let portable (cs: Callstack.t) =
  { thread = cs.thread;
    entry = Kernel_function.get_name cs.entry_point;
    calls =
      List.map
        (fun (kf, stmt) -> Kernel_function.get_name kf, stmt.Cil_types.sid)
        cs.stack }

(* A callstack is identified by its printed form and its portable form: two
   calls of a function on one source line are printed alike. *)
let seen : (string, portable list) Hashtbl.t = Hashtbl.create 17

let identify callstack =
  let printed = string_of_callstack callstack and p = portable callstack in
  let known = Option.value ~default:[] (Hashtbl.find_opt seen printed) in
  if not (List.mem p known) then Hashtbl.replace seen printed (p :: known);
  printed, p

(* The name shown for a callstack: its printed form, with the numbers of its
   call statements, and its thread if needed, when another callstack is
   printed alike. It is used for output only: callstacks are looked up by
   their identity. *)
let display (printed, p) =
  match Hashtbl.find_opt seen printed with
  | Some (_ :: _ :: _ as alike) ->
    let sids = List.map (fun (_, sid) -> string_of_int sid) p.calls in
    let thread =
      if List.for_all (fun p' -> p'.thread = p.thread) alike then ""
      else Format.sprintf "thread %d, " p.thread
    in
    Format.sprintf "%s (%scall statements %s)" printed thread
      (String.concat ", " sids)
  | _ -> printed

let observing_calls = ref false
let calls = ref []

(* The calls of the analysis that have started, with their function. A call
   that has started and has no results is interrupted. *)
let started = ref []

(* The starts and the results of the calls of the analysis, most recent
   first, and whether an exception stopped the analysis. *)
type event = Start of portable | End of portable * string
let events = ref []
let stopped = ref false

let () =
  Cvalue_callbacks.register_call_hook
    (fun callstack kf _state _kind ->
       if !observing_calls then begin
         started := (portable callstack, kf) :: !started;
         events := Start (portable callstack) :: !events
       end)

(* In the summary mode, the footprint that InOut gives for each call analysed
   by its body, by number of its cache entry, until the results of the call
   are known; then the numbers of the calls whose footprint is unknown for
   the rule: absent, or with a zone or a state that is top at a point. *)
let footprints = Hashtbl.create 17
let unknown_footprints = Hashtbl.create 17

let () =
  Cmdline.run_after_configuring_stage
    (fun () ->
       let zones = Datatype.pair Memory_zone.ty Memory_zone.ty in
       let footprint = Datatype.func Cil_datatype.Stmt.ty zones in
       let typ = Datatype.(func (func (pair int footprint) unit) unit) in
       if suite then
         match Dynamic.get ~plugin:"Inout" "register_footprint_hook" typ with
         | register ->
           register
             (fun (id, f) ->
                if !observing_calls then Hashtbl.replace footprints id f)
         | exception
             (Failure _ | Dynamic.(Unbound_value _ | Incompatible_type _)) ->
           ())

let is_top_zone = function
  | Memory_zone.Top (Base.SetLattice.Top, _) -> true
  | _ -> false

let is_top_state = function Cvalue.Model.Top -> true | _ -> false

(* As the rule of #87 does, the zones before the statements, and after them
   with those before their successors, at the points reached by the call. *)
let record_footprint id start (states : Cvalue_callbacks.results) =
  let unknown =
    match Hashtbl.find_opt footprints id with
    | None -> true
    | Some footprint ->
      Hashtbl.remove footprints id;
      let before stmt = is_top_zone (fst (footprint stmt)) in
      let after (stmt: Cil_types.stmt) =
        is_top_zone (snd (footprint stmt)) || List.exists before stmt.succs
      in
      let unknown_at zone table =
        Cil_datatype.Stmt.Hashtbl.fold
          (fun stmt state acc -> acc || is_top_state state || zone stmt)
          (Lazy.force table) false
      in
      is_top_state start
      || unknown_at before states.before_stmts
      || unknown_at after states.after_stmts
  in
  if unknown then Hashtbl.replace unknown_footprints id ()

let () =
  Cvalue_callbacks.register_call_results_hook
    (fun callstack kf state results ->
       if !observing_calls && suite then begin
         match results with
         | `Body (states, id) -> record_footprint id state states
         | `Reuse _ | `Spec _ | `Builtin _ -> ()
       end;
       if !observing_calls then
         events :=
           End (portable callstack, Kernel_function.get_name kf) :: !events;
       if !observing_calls then
         let kind =
           match results with
           | `Body (_, id) -> Analysed id
           | `Reuse id -> Hit id
           | `Spec _ -> Other "specification"
           | `Builtin _ -> Other "builtin"
         in
         calls := (identify callstack, kf, kind) :: !calls)

let print_calls () =
  Format.printf "@[<v 2>Calls:";
  List.iter
    (fun (callstack, _kf, kind) ->
       let callstack = display callstack in
       match kind with
       | Analysed id ->
         Format.printf "@ %s: analysed, cache entry %d" callstack id
       | Hit id -> Format.printf "@ %s: hit of cache entry %d" callstack id
       | Other s -> Format.printf "@ %s: %s" callstack s)
    (List.rev !calls);
  Format.printf "@]@."

(* The callstacks that reach the start of a function and are not those of a
   call of the analysis. [starts] gives the callstacks of each start. Returns
   their printed forms. *)
let print_below starts =
  let observed = List.map (fun ((_, p), _, _) -> p) !calls in
  let below =
    List.concat starts
    |> List.filter (fun (_, p) -> not (List.mem p observed))
    |> List.sort_uniq compare
  in
  if below <> [] then begin
    Format.printf "@[<v 2>Calls below a hit:";
    List.iter (fun stack -> Format.printf "@ %s" (display stack)) below;
    Format.printf "@]@."
  end;
  List.map fst below

(* ----- Points ------------------------------------------------------------ *)

type point = {
  description: string;
  request: Results.request;
  trap: string; (* The point, as Eva.Legacy_read_trap describes it. *)
  kf: Kernel_function.t option; (* The function of the point. *)
  show: bool; (* Whether its states are printed. *)
  kind: string; (* The kind of point, for the summary. *)
}

(* In the summary mode, the names of the functions without a body that are
   called in the reference, sorted. *)
let without_body = ref []

let called_without_body () =
  let names = ref [] in
  Globals.Functions.iter
    (fun kf ->
       if not (Kernel_function.is_definition kf) && Results.is_called kf
       then names := Kernel_function.get_name kf :: !names);
  List.sort String.compare !names

(* The built-ins whose call the kernel printer completes with the last named
   formal of the current function: outside the printing of a function, it
   reports a failure. *)
let completed_builtins =
  [ "__builtin_next_arg"; "__builtin_va_start"; "__builtin_stdarg_start";
    "__builtin_c23_va_start" ]

(* A statement, shortened to one line. *)
let pretty_stmt fmt stmt =
  match stmt.Cil_types.skind with
  | Instr (Call (result, Var vi, args, _))
    when List.mem vi.vname completed_builtins ->
    Option.iter (Format.fprintf fmt "%a = " Printer.pp_lval) result;
    Format.fprintf fmt "%s(%a);" vi.vname
      (Pretty_utils.pp_list ~sep:", " Printer.pp_exp) args
  | Instr instr ->
    let text = Format.asprintf "%a" Printer.pp_instr instr in
    let text = String.map (function '\n' -> ' ' | c -> c) text in
    Format.pp_print_string fmt text
  | Return (None, _) -> Format.pp_print_string fmt "return;"
  | Return (Some e, _) -> Format.fprintf fmt "return %a;" Printer.pp_exp e
  | If (e, _, _, _) -> Format.fprintf fmt "if (%a)" Printer.pp_exp e
  | Switch (e, _, _, _) -> Format.fprintf fmt "switch (%a)" Printer.pp_exp e
  | Loop _ -> Format.pp_print_string fmt "loop"
  | Block _ -> Format.pp_print_string fmt "block"
  | UnspecifiedSequence _ -> Format.pp_print_string fmt "sequence"
  | Goto _ -> Format.pp_print_string fmt "goto"
  | Break _ -> Format.pp_print_string fmt "break;"
  | Continue _ -> Format.pp_print_string fmt "continue;"
  | Throw _ | TryCatch _ | TryFinally _ | TryExcept _ ->
    Format.pp_print_string fmt "exception"

let labels stmt =
  List.filter_map
    (function Cil_types.Label (name, _, true) -> Some name | _ -> None)
    stmt.Cil_types.labels

let describe_stmt position stmt =
  let kf = Kernel_function.find_englobing_kf stmt in
  Format.asprintf "%s, %s %a `%a`%s" (Kernel_function.get_name kf) position
    Fileloc.pretty (Cil_datatype.Stmt.loc stmt) pretty_stmt stmt
    (match labels stmt with [] -> "" | l -> " (" ^ String.concat ", " l ^ ")")

let trap_stmt position stmt =
  Format.asprintf "%s %a in %a" position
    Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
    Kernel_function.pretty (Kernel_function.find_englobing_kf stmt)

(* The initial and final states of the analysis, then the points of the
   functions with a body, in the order of the source. The states are printed
   at the start, at the labelled statements and at the end of the functions
   that have labels and are called. *)
let points () =
  let functions = ref [] in
  Globals.Functions.iter
    (fun kf ->
       if Kernel_function.is_definition kf
       then functions := kf :: !functions);
  let functions =
    List.sort
      (fun kf kf' ->
         Fileloc.compare
           (Kernel_function.get_location kf) (Kernel_function.get_location kf'))
      !functions
  in
  let of_function kf =
    let stmts = (Kernel_function.get_definition kf).sallstmts in
    let labelled =
      Results.is_called kf && List.exists (fun stmt -> labels stmt <> []) stmts
    in
    let return = Kernel_function.find_return kf in
    let start =
      { description = Kernel_function.get_name kf ^ ", start";
        request = Results.at_start_of kf;
        trap = "start of " ^ Kernel_function.get_name kf;
        kf = Some kf; show = labelled; kind = "start" }
    in
    let of_stmt stmt =
      [ { description = describe_stmt "before" stmt;
          request = Results.before stmt; trap = trap_stmt "before" stmt;
          kf = Some kf; show = labelled && labels stmt <> [];
          kind = "before" };
        { description = describe_stmt "after" stmt;
          request = Results.after stmt; trap = trap_stmt "after" stmt;
          kf = Some kf;
          show = labelled && Cil_datatype.Stmt.equal stmt return;
          kind = "after" } ]
    in
    start :: List.concat_map of_stmt stmts
  in
  let of_declaration name =
    let kf = Globals.Functions.find_by_name name in
    { description = name ^ ", start, without body";
      request = Results.at_start_of kf; trap = "start of " ^ name;
      kf = Some kf; show = false; kind = "start without body" }
  in
  let main = fst (Globals.entry_point ()) in
  (* An entry point without a body has no final state. *)
  let final =
    match Kernel_function.find_return main with
    | return ->
      [ { description = "final state"; request = Results.at_end ();
          trap = trap_stmt "after" return;
          kf = None; show = false; kind = "final" } ]
    | exception Kernel_function.No_Statement -> []
  in
  { description = "initial state"; request = Results.at_start;
    trap = "initial state"; kf = None; show = false; kind = "initial" }
  :: final
  @ List.concat_map of_function functions
  @ List.map of_declaration !without_body

(* ----- Requests ---------------------------------------------------------- *)

type answer = Cvalue.Model.t Results.result

(* In the current project, each request is checked against the report of
   Eva.Legacy_read_trap: it must add one request to the report, with the
   description expected. *)
let checking = ref false
let made = ref 0
let unmatched = ref [] (* Expected description and descriptions added. *)

(* The number of requests made in the current project, by kind of point and
   kind of request. *)
let made_by_kind = Hashtbl.create 17

let request ?(point = "") ~what ~expected f =
  if not !checking then f ()
  else begin
    let key = point, what in
    let n = Option.value ~default:0 (Hashtbl.find_opt made_by_kind key) in
    Hashtbl.replace made_by_kind key (n + 1);
    let before = List.length (Legacy_read_trap.requests ()) in
    let result = f () in
    incr made;
    let added =
      List.filteri (fun i _ -> i >= before) (Legacy_read_trap.requests ())
      |> List.map (fun r -> r.Legacy_read_trap.description)
    in
    begin match added with
      | [ description ] when String.equal description expected -> ()
      | _ -> unmatched := (expected, added) :: !unmatched
    end;
    result
  end

let rebuild p : Callstack.t =
  let kf = Globals.Functions.find_by_name in
  { thread = p.thread;
    entry_point = kf p.entry;
    stack =
      List.map
        (fun (name, sid) -> kf name, fst (Kernel_function.find_from_sid sid))
        p.calls }

(* The callstacks of the projects are paired by their portable form. *)
let callstacks (point : point) =
  request ~point:point.kind ~what:"callstacks"
    ~expected:(point.trap ^ "; every callstack")
    (fun () -> Results.callstacks point.request)
  |> List.map identify
  |> List.sort compare

(* The callstacks that reach a point in one of the projects. *)
let union lists =
  List.sort_uniq compare (List.concat lists)

(* The answers at one point. *)
type point_answers = {
  joined: answer;
  filtered: answer;
  by_callstack: ((string * portable) * answer) list;
  filtered_stacks: portable list; (* The callstacks the filter keeps. *)
}

(* The number of points of the current project at which the filter rejects
   a callstack. *)
let rejecting = ref 0

(* The answers at [point], for the callstacks [stacks]. With several
   callstacks, the filter rejects the first one. *)
let answers (point : point) stacks =
  let state ~what ~expected request_ =
    request ~point:point.kind ~what ~expected
      (fun () -> Results.get_cvalue_model_result request_)
  in
  let joined =
    state ~what:"joined" ~expected:(point.trap ^ "; joined") point.request
  in
  let keep =
    match stacks with
    | (_, rejected) :: _ :: _ ->
      if !checking then incr rejecting;
      fun cs -> portable cs <> rejected
    | _ -> fun _ -> true
  in
  let filtered =
    state ~what:"filtered"
      ~expected:(point.trap ^ "; every callstack, filtered")
      Results.(point.request |> filter_callstack keep)
  in
  let by_callstack =
    List.map
      (fun (printed, cs as stack) ->
         let expected = point.trap ^ "; callstack " ^ printed in
         stack,
         state ~what:"callstack" ~expected
           Results.(point.request |> in_callstack (rebuild cs)))
      stacks
  in
  let filtered_stacks =
    request ~point:point.kind ~what:"callstacks, filtered"
      ~expected:(point.trap ^ "; every callstack, filtered")
      (fun () ->
         Results.(callstacks (point.request |> filter_callstack keep)))
    |> List.map portable |> List.sort compare
  in
  { joined; filtered; by_callstack; filtered_stacks }


(* ----- Comparison -------------------------------------------------------- *)

type verdict = Equal | Covers | More_precise | Omits | Unavailable

(* The model of an answer, or None if it is unavailable. *)
let model = function
  | Ok Cvalue.Model.Top | Error (Results.Top | DisabledDomain) -> None
  | Ok state -> Some state
  | Error Results.Bottom -> Some Cvalue.Model.bottom

let verdict ~reference ~answer =
  match model reference, model answer with
  | _, None -> Unavailable
  | None, Some _ -> Omits
  | Some reference, Some answer ->
    match Cvalue.Model.is_included reference answer,
          Cvalue.Model.is_included answer reference with
    | true, true -> Equal
    | true, false -> Covers
    | false, true -> More_precise
    | false, false -> Omits

let string_of_verdict = function
  | Equal -> "equal"
  | Covers -> "covers"
  | More_precise -> "more precise"
  | Omits -> "OMITS"
  | Unavailable -> "unavailable"

(* The answers of the three projects at one point. *)
type compared = {
  reference: point_answers; (* Without memexec. *)
  memexec: point_answers; (* With memexec, without recording. *)
  current: point_answers; (* With recording. *)
}

(* The three projects are asked for the same callstacks at each point. *)
let find name list = List.assoc name list

(* ----- Cases of the closed list ------------------------------------------ *)

(* In the summary mode, the case of the closed list of #87 that the run shows
   for an unavailable answer at a point of a function, from the options, the
   calls of the analysis with -eva-hit-log, and the footprints that InOut
   gives for them. Calls below a hit, the first case of the list, are
   answered since #91 and are not a case. *)

(* Whether a call of a function analysed by its body has an unknown
   footprint. *)
let unknown_footprint name =
  List.exists
    (fun (_, kf, kind) ->
       match kind with
       | Analysed id ->
         String.equal (Kernel_function.get_name kf) name
         && Hashtbl.mem unknown_footprints id
       | Hit _ | Other _ -> false)
    !calls

(* Whether a function has a call of the analysis analysed by its body, or a
   hit, on a callstack where it is already called: its recursive calls are
   unrolled. *)
let unrolled name =
  List.exists
    (fun ((_, p), _, kind) ->
       match kind with
       | Analysed _ | Hit _ ->
         let frames = p.entry :: List.map fst p.calls in
         List.length (List.filter (String.equal name) frames) >= 2
       | Other _ -> false)
    !calls

(* The functions of the calls in progress when an exception stopped the
   analysis. Eva then runs the hooks on the results of each call in
   progress, from the innermost, and starts no call: these are the results
   that end the analysis, each of the caller of the previous one. The last
   call that ended before the stop, if called by a call in progress, is
   among them: the hooks do not tell it apart. *)
let in_progress_at_stop () =
  let extends caller callee =
    caller.thread = callee.thread && String.equal caller.entry callee.entry
    && match callee.calls with
    | _ :: calls -> calls = caller.calls
    | [] -> false
  in
  let rec chain caller acc = function
    | End (p, name) :: rest when extends caller p -> chain p (name :: acc) rest
    | _ -> acc
  in
  match !events with
  | End (p, name) :: rest when !stopped && p.calls = [] -> chain p [ name ] rest
  | _ -> []

(* Whether a call of a function has started and has no results, or was in
   progress when an exception stopped the analysis. *)
let interrupted name =
  List.mem name (in_progress_at_stop ()) ||
  let callstacks =
    List.sort_uniq compare
      (List.filter_map
         (fun (p, kf) ->
            if String.equal (Kernel_function.get_name kf) name then Some p
            else None)
         !started)
  in
  List.exists
    (fun p ->
       let n_started =
         List.length (List.filter (fun (p', _) -> p' = p) !started)
       and n_results =
         List.length (List.filter (fun ((_, p'), _, _) -> p' = p) !calls)
       in
       n_started > n_results)
    callstacks

(* Whether the call of the function [name] at the statement [sid] may rename
   variables if it is a recursive call: the function has a formal or a local
   whose address is taken, or that an argument of the call copies, the
   argument being an lvalue of this variable. *)
let renames name sid =
  let kf = Globals.Functions.find_by_name name in
  let vars = Kernel_function.get_formals kf @ Kernel_function.get_locals kf in
  let args =
    match (fst (Kernel_function.find_from_sid sid)).Cil_types.skind with
    | Instr (Call (_, _, args, _))
    | Instr (Local_init (_, ConsInit (_, args, _), _)) -> args
    | _ -> []
  in
  let copies vi (arg: Cil_types.exp) =
    match arg.enode with
    | Lval (Var v, _) -> Cil_datatype.Varinfo.equal v vi
    | _ -> false
  in
  List.exists
    (fun vi -> vi.Cil_types.vaddrof || List.exists (copies vi) args)
    vars

(* The callstacks of the calls below a hit, each with whether it crosses a
   recursion: from the hit down, one of its calls is a recursive call that
   renames variables, its function being already on the callstack of its
   caller, whether its counterpart was analysed by its body or by its
   specification. The counterpart of a call below a hit is the call made at
   the same statement by the analysed call of the cache entry that its
   caller uses. These callstacks are rebuilt from the calls of the analysis,
   from each hit down, as the rule of #87 does. *)
let crossing_callstacks =
  lazy begin
    let table = Hashtbl.create 17 in
    let analysed = Hashtbl.create 17 and children = Hashtbl.create 17 in
    List.iter
      (fun ((_, p), _, kind) ->
         begin match kind with
           | Analysed id -> Hashtbl.replace analysed id p
           | Hit _ | Other _ -> ()
         end;
         match p.calls with
         | call :: calls -> Hashtbl.add children { p with calls } (call, kind)
         | [] -> ())
      !calls;
    (* [walk q crossing id] adds the callstacks below the call on [q], which
       uses the cache entry [id] and does not run its body. *)
    let rec walk q crossing id =
      match Hashtbl.find_opt analysed id with
      | None -> ()
      | Some a ->
        let frames = q.entry :: List.map fst q.calls in
        List.iter
          (fun ((name, sid as call), kind) ->
             let p = { q with calls = call :: q.calls } in
             let entry =
               match kind with
               | Analysed id | Hit id -> Some id
               | Other _ -> None
             in
             let crossing =
               crossing || List.mem name frames && renames name sid
             in
             let previous = Hashtbl.find_opt table p = Some true in
             Hashtbl.replace table p (previous || crossing);
             Option.iter (walk p crossing) entry)
          (Hashtbl.find_all children a)
    in
    List.iter
      (fun ((_, p), _, kind) ->
         match kind with
         | Hit id -> walk p false id
         | Analysed _ | Other _ -> ())
      !calls;
    table
  end

(* Whether one of the callstacks [stacks] is that of a call below a hit that
   crosses a recursion. *)
let crossing stacks =
  let table = Lazy.force crossing_callstacks in
  List.exists (fun p -> Hashtbl.find_opt table p = Some true) stacks

(* The case of an unavailable answer at [point] that includes the callstacks
   [stacks]. The cases are numbered as in the closed list of #87. The points
   of the body of a call below a hit that crosses a recursion are rebuilt
   from its start, and are unavailable with it: they are told apart, as
   case 3b. *)
let closed_list_case (point : point) ~stacks =
  let name =
    match point.kf, point.kind with
    | Some kf, _ -> Some (Kernel_function.get_name kf)
    | None, "final" ->
      Some (Kernel_function.get_name (fst (Globals.entry_point ())))
    | None, _ -> None
  in
  let results_disabled name =
    not (Analysis.save_results (Globals.Functions.find_by_name name))
  in
  let start = List.mem point.kind [ "start"; "start without body" ] in
  if not (Parameters.ResultsAll.get ())
  || Parameters.NoResultsDomain.mem "cvalue"
  then "results of the cvalue domain disabled"
  else
    match name with
    | None -> "none"
    | Some _ when start ->
      if crossing stacks then "3: start below a hit, across a recursion"
      else "none"
    | Some name ->
      if results_disabled name then "5: results disabled"
      else if unrolled name then "2: unrolled recursive calls"
      else if interrupted name then "4: interrupted call"
      else if unknown_footprint name then "6: unknown footprint"
      else if crossing stacks then "3b: body below a hit, across a recursion"
      else "none"

(* ----- Comparison of the answers ----------------------------------------- *)

let counts = Hashtbl.create 5
let memexec_counts = Hashtbl.create 5

let count table v =
  let n = Option.value ~default:0 (Hashtbl.find_opt table v) in
  Hashtbl.replace table v (n + 1)

(* [stacks] are the callstacks that [answer] includes in the current
   project. *)
let compare_answer point ~what ~stacks description ~reference ~memexec
    ~answer =
  let v = verdict ~reference ~answer in
  let v_memexec = verdict ~reference ~answer:memexec in
  count counts v;
  count memexec_counts v_memexec;
  let origin =
    if v = Unavailable && model reference = None then ", as in the reference"
    else if verdict ~reference:memexec ~answer = Equal
    then ", as with memexec"
    else ""
  in
  if v <> Equal then
    Format.printf "  %s: %s%s@." description (string_of_verdict v) origin;
  if suite && (v <> Equal || v_memexec <> Equal) then
    let name = match point.kf with
      | Some kf -> Kernel_function.get_name kf
      | None -> ""
    in
    let case =
      if v = Unavailable then closed_list_case point ~stacks else ""
    in
    record [ "answer"; point.kind; name; description; what;
             string_of_verdict v; string_of_verdict v_memexec;
             String.trim (Str.global_replace (Str.regexp "^, ") "" origin);
             case ]

(* [listed] are the callstacks that reach [point] in the current project. *)
let compare_point point c ~listed =
  let describe what = point.description ^ ", " ^ what in
  compare_answer point ~what:"joined" ~stacks:listed (describe "joined")
    ~reference:c.reference.joined
    ~memexec:c.memexec.joined ~answer:c.current.joined;
  compare_answer point ~what:"filtered" ~stacks:c.current.filtered_stacks
    (describe "filtered")
    ~reference:c.reference.filtered
    ~memexec:c.memexec.filtered ~answer:c.current.filtered;
  List.iter
    (fun ((_, p as name), answer) ->
       compare_answer point ~what:"callstack" ~stacks:[ p ]
         (describe (display name))
         ~reference:(find name c.reference.by_callstack)
         ~memexec:(find name c.memexec.by_callstack)
         ~answer)
    c.current.by_callstack

(* ----- Allocated blocks -------------------------------------------------- *)

(* The bases of allocated blocks, and the variables that Eva creates during
   the analysis, as those of the context of option -lib-entry and the copies
   of the locals of recursive calls, are created by each analysis, with
   another identity in each project, and sometimes with a counter shared by
   the projects in their name. The bases are matched across projects by
   their name without the suffixes of the counter, and by their rank of
   creation. The variables that exist before the analyses have the same
   identity in the three projects, which are copies. *)

let existing_variables = ref Cil_datatype.Varinfo.Set.empty

let collect_existing_variables () =
  let set = ref Cil_datatype.Varinfo.Set.empty in
  let add vi = set := Cil_datatype.Varinfo.Set.add vi !set in
  Globals.Vars.iter (fun vi _ -> add vi);
  Globals.Functions.iter
    (fun kf ->
       add (Kernel_function.get_vi kf);
       List.iter add (Kernel_function.get_formals kf);
       if Kernel_function.is_definition kf
       then List.iter add (Kernel_function.get_locals kf));
  existing_variables := !set

let created_by_analysis = function
  | Base.Allocated _ -> true
  | Base.Var (vi, _) ->
    not (Cil_datatype.Varinfo.Set.mem vi !existing_variables)
  | _ -> false

(* The created bases bound in the states of [answers], or present in their
   values: a block of size zero, as the context of an empty structure, has
   no binding. *)
let allocated_bases answers =
  let add_base base acc =
    if created_by_analysis base then Base.Hptset.add base acc else acc
  in
  let add_value v acc =
    try Cvalue.V.fold_bases add_base (Cvalue.V_Or_Uninitialized.get_v v) acc
    with Abstract_interp.Error_Top -> acc
  in
  let add acc = function
    | Ok (Cvalue.Model.Map map) ->
      Cvalue.Model.fold
        (fun base offsetmap acc ->
           add_base base acc
           |> Cvalue.V_Offsetmap.fold_on_values add_value offsetmap)
        map acc
    | _ -> acc
  in
  List.fold_left
    (fun acc a ->
       List.fold_left add acc
         (a.joined :: a.filtered :: List.map snd a.by_callstack))
    Base.Hptset.empty answers

let counter_suffix = Str.regexp "\\(_[0-9]+\\)+$"

(* Each allocated base with its key: its name without the suffix of the
   counter, and its rank among the bases of that name. *)
let ranked answers =
  let bases =
    allocated_bases answers |> Base.Hptset.elements
    |> List.sort (fun b b' -> Int.compare (Base.id b) (Base.id b'))
  in
  let ranks = Hashtbl.create 7 in
  List.map
    (fun base ->
       let name = (Base.to_varinfo base).vname in
       let name = Str.global_replace counter_suffix "" name in
       let rank = Option.value ~default:0 (Hashtbl.find_opt ranks name) in
       Hashtbl.replace ranks name (rank + 1);
       (name, rank), base)
    bases

(* Renames the allocated bases of [answers] into those of [into]. *)
let rename ~into answers =
  let into = ranked into in
  let substitution =
    ranked answers
    |> List.filter_map
      (fun (key, base) ->
         Option.map (fun base' -> base, base') (List.assoc_opt key into))
    |> Base.substitution_from_list
  in
  let rename_value v =
    snd (Cvalue.V_Or_Uninitialized.replace_base substitution v)
  in
  let rename_model = function
    | Cvalue.Model.Map map ->
      Cvalue.Model.fold
        (fun base offsetmap acc ->
           Cvalue.Model.add_base base
             (Cvalue.V_Offsetmap.map_on_values rename_value offsetmap) acc)
        map Cvalue.Model.empty_map
      |> Cvalue.Model.replace_base substitution
    | model -> model
  in
  let rename_answer answer = Result.map rename_model answer in
  List.map
    (fun a ->
       { joined = rename_answer a.joined;
         filtered = rename_answer a.filtered;
         by_callstack =
           List.map (fun (cs, a) -> cs, rename_answer a) a.by_callstack;
         filtered_stacks = a.filtered_stacks })
    answers

(* ----- Printing of states ------------------------------------------------ *)

(* Whether a base is printed: the variables of the source file, without those
   of the library. *)
let shown base =
  match Base.to_varinfo base with
  | vi -> not (Cil.is_in_libc vi.vattr)
  | exception Base.Not_a_C_variable -> not (Base.is_string_literal base)

let pretty_state fmt = function
  | Error Results.Bottom -> Format.pp_print_string fmt "unreachable"
  | Ok Cvalue.Model.Top | Error (Results.Top | DisabledDomain) ->
    Format.pp_print_string fmt "unavailable"
  | Ok state ->
    Cvalue.Model.pretty fmt (Cvalue.Model.filter_base shown state)

let print_answers title answers =
  Format.printf "@ %s: @[%a@]" title pretty_state answers.joined;
  List.iter
    (fun (name, answer) ->
       Format.printf "@ %s: @[%a@]" (display name) pretty_state answer)
    answers.by_callstack

let all_equal c =
  verdict ~reference:c.reference.joined ~answer:c.current.joined = Equal
  && List.length c.reference.by_callstack = List.length c.current.by_callstack
  && List.for_all
    (fun (name, answer) ->
       verdict ~reference:(find name c.reference.by_callstack) ~answer = Equal)
    c.current.by_callstack

let print_labelled (point, c) =
  if point.show then begin
    Format.printf "@[<v 2>%s:" point.description;
    print_answers "joined" c.current;
    if not (all_equal c) then
      print_answers "reference, joined" c.reference;
    Format.printf "@]@."
  end

(* ----- Control of the hits ----------------------------------------------- *)

(* The printed variables whose values differ between two answers. *)
let differing_variables a b =
  match model a, model b with
  | Some (Cvalue.Model.Map map_a as a), Some (Cvalue.Model.Map map_b as b) ->
    let bases map =
      Cvalue.Model.fold (fun base _ acc -> Base.Hptset.add base acc)
        map Base.Hptset.empty
    in
    let find base model =
      try Some (Cvalue.Model.find_base base model) with Not_found -> None
    in
    let differ base =
      match find base a, find base b with
      | Some (`Value x), Some (`Value y) -> not (Cvalue.V_Offsetmap.equal x y)
      | Some `Bottom, Some `Bottom | Some `Top, Some `Top -> false
      | _ -> true
    in
    Base.Hptset.union (bases map_a) (bases map_b)
    |> Base.Hptset.filter (fun base -> shown base && differ base)
    |> Base.Hptset.elements
    |> List.map (Format.asprintf "%a" Base.pretty)
  | Some Cvalue.Model.Bottom, Some Cvalue.Model.Bottom -> []
  | _ -> [ "the whole state" ]

(* For each hit on another callstack than the analysed call of its cache
   entry, the variables whose values differ between the answers on the two
   callstacks, at the points of the function where both are available. *)
let print_control compared =
  let analysed id =
    List.find_map
      (fun (cs, _, kind) -> if kind = Analysed id then Some cs else None)
      !calls
  in
  let control (hit, kf, kind) =
    match kind with
    | Hit id ->
      begin match analysed id with
        | Some entry when entry <> hit ->
          let points = ref 0 and unavailable = ref 0 and variables = ref [] in
          List.iter
            (fun (point, c) ->
               if Option.equal Kernel_function.equal point.kf (Some kf)
               then begin
                 incr points;
                 let find name list =
                   Option.value ~default:(Error Results.Bottom)
                     (List.assoc_opt name list)
                 in
                 let a = find entry c.current.by_callstack in
                 let b = find hit c.current.by_callstack in
                 if model a = None || model b = None then incr unavailable
                 else variables := differing_variables a b @ !variables
               end)
            compared;
          let variables = List.sort_uniq String.compare !variables in
          let summary =
            if !unavailable = !points then "unavailable"
            else if variables = [] then "no difference"
            else "differs on " ^ String.concat ", " variables
          in
          let summary =
            if !unavailable = 0 || !unavailable = !points then summary
            else Format.sprintf "%s, unavailable at %d points" summary
                !unavailable
          in
          Format.printf "  %s, hit of cache entry %d, against %s: %s, at %d \
                         points.@."
            (display hit) id (display entry) summary !points
        | _ -> ()
      end
    | Analysed _ | Other _ -> ()
  in
  if List.exists (function (_, _, Hit _) -> true | _ -> false) !calls then
    Format.printf "Hits against the analysed call of their cache entry:@.";
  List.iter control (List.rev !calls)

(* ----- Passes after the iteration ---------------------------------------- *)

(* What an analysis gives after its iteration: the requests and the reads
   outside any request that Eva.Legacy_read_trap reports, made by the passes
   or outside them, as by the hooks, and the messages printed by the
   passes. *)
type passes = {
  requests: Legacy_read_trap.request list;
  strays: Legacy_read_trap.stray list;
  output: string;
}

(* The messages printed from the end of the iteration, when Eva has results,
   to the end of the analysis, by the passes, are captured. *)
let capture = ref None

let () =
  Analysis.register_computation_hook ~on:Computed
    (fun _ ->
       Option.iter
         (fun (_, fmt) -> Log.set_formatter ~isatty:false fmt)
         !capture)

let analyse () =
  let buffer = Buffer.create 80 in
  let fmt = Format.formatter_of_buffer buffer in
  capture := Some (buffer, fmt);
  Legacy_read_trap.start ();
  begin
    try Analysis.compute ()
    with Log.AbortError _ ->
      if !observing_calls then stopped := true;
      record [ "stopped" ];
      Format.printf "The analysis has stopped.@."
  end;
  Legacy_read_trap.stop ();
  capture := None;
  Format.pp_print_flush fmt ();
  Log.reset_stdout ~isatty:false ();
  { requests = Legacy_read_trap.requests ();
    strays = Legacy_read_trap.stray_reads ();
    output = Buffer.contents buffer }

let reads_of passes =
  List.length (List.concat_map (fun r -> r.Legacy_read_trap.reads)
                 passes.requests)

let plural ?plural n word =
  let words = Option.value ~default:(word ^ "s") plural in
  Format.sprintf "%d %s" n (if n = 1 then word else words)

(* The passes in the order of their first request, with their number of
   requests. The requests made outside the passes are counted together. *)
let by_pass passes =
  List.fold_left
    (fun acc r ->
       let name =
         Option.value ~default:"outside the passes" r.Legacy_read_trap.pass
       in
       if List.mem_assoc name acc
       then List.map (fun (n, c) -> n, if n = name then c + 1 else c) acc
       else acc @ [ name, 1 ])
    [] passes.requests

(* [below] are the printed callstacks of the calls below a hit. *)
let print_passes ~memexec ~current ~below =
  let summary what passes =
    Format.printf "  %s: %s, %s of the legacy store in them, %s outside any \
                   request.@." what
      (plural (List.length passes.requests) "request")
      (plural (reads_of passes) "read")
      (plural (List.length passes.strays) "read")
  in
  Format.printf "Passes after the iteration:@.";
  summary "with memexec, without recording" memexec;
  summary "with -eva-hit-log" current;
  List.iter
    (fun (name, n) ->
       Format.printf "    %s: %s@." name (plural n "request"))
    (by_pass current);
  if below <> [] then begin
    let on_below r =
      List.exists
        (fun cs ->
           let suffix = "; callstack " ^ cs in
           String.ends_with ~suffix r.Legacy_read_trap.description)
        below
    in
    Format.printf "  requests of the passes on a callstack below a hit, with \
                   -eva-hit-log: %d.@."
      (List.length (List.filter on_below current.requests))
  end;
  List.iter
    (fun r -> if r.Legacy_read_trap.reads <> [] then
        Format.printf "  %a@." Legacy_read_trap.pretty_request r)
    current.requests;
  List.iter (Format.printf "  %a@." Legacy_read_trap.pretty_stray)
    current.strays

(* ----- Outputs of the passes --------------------------------------------- *)

let one_line = Str.global_replace (Str.regexp "[ \n]+") " "

(* The status of each property, by its location, its description and its
   text: the description of an alarm does not give its expression. The flag
   tells a property of reachability. *)
let statuses () =
  let list = ref [] in
  Property_status.iter
    (fun ip ->
       let key =
         Format.asprintf "%a: %a: %a" Fileloc.pretty (Property.location ip)
           Description.pp_property ip Property.pretty ip
         |> one_line
       in
       let reachability =
         match ip with Property.IPReachable _ -> true | _ -> false
       in
       list := (key, (reachability, Property_status.Feedback.get ip)) :: !list);
  List.sort_uniq compare !list

(* The alarms, by their statement and their text, with their status. Scope
   does not remove a redundant alarm: it gives it a valid status under the
   hypothesis of the alarm that makes it redundant. *)
let alarms () =
  let list = ref [] in
  Alarms.iter
    (fun _emitter kf stmt ~rank:_ alarm ca ->
       let ip = Property.ip_of_code_annot_single kf stmt ca in
       let alarm =
         Format.asprintf "%a: %a" Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
           Alarms.pretty alarm
         |> one_line
       in
       list := (alarm, Property_status.Feedback.get ip) :: !list);
  List.sort_uniq compare !list

(* The statement and function coverage and the number of alarms computed by
   the summary. *)
let summary_statistics () =
  Statistics.(get stmt_coverage (), get fun_coverage (), get alarm_count ())

(* The rank of a status, from the most pessimistic. A property absent from
   a project, as an alarm that is not emitted, is ranked as valid. For a
   property of reachability, an invalid status claims that the statement is
   unreachable: it is ranked as the most optimistic, and the absence of the
   property, which claims nothing, below it. *)
let rank ?(reachability = false) : Property_status.Feedback.t option -> int =
  function
  | Some (Invalid | Invalid_under_hyp | Invalid_but_dead) when reachability ->
    2
  | None when reachability -> 1
  | Some (Invalid | Invalid_under_hyp) -> 0
  | Some (Unknown | Never_tried | Inconsistent) -> 1
  | None | Some (Valid | Valid_under_hyp | Considered_valid | Valid_but_dead
                | Unknown_but_dead | Invalid_but_dead) -> 2

let string_of_status = function
  | None -> "absent"
  | Some status -> Description.status_feedback status

type outputs = {
  statuses: (string * (bool * Property_status.Feedback.t)) list;
  alarms: (string * Property_status.Feedback.t) list;
  statistics: float * float * int;
  output: string;
}

let outputs project (passes: passes) =
  Project.on project
    (fun () ->
       { statuses = statuses (); alarms = alarms ();
         statistics = summary_statistics (); output = passes.output })
    ()

(* The statuses of [o] that differ from those of [reference]: the property,
   the two statuses, the verdict and the origin. *)
let status_differences keys ~reference ~memexec o =
  List.filter_map
    (fun key ->
       let find o = Option.map snd (List.assoc_opt key o.statuses) in
       let reachability =
         List.exists (fun (k, (r, _)) -> k = key && r)
           (reference.statuses @ o.statuses)
       in
       let rank = rank ~reachability in
       let r = find reference and c = find o in
       if r = c then None
       else
         let verdict =
           if rank c > rank r then "MORE OPTIMISTIC"
           else if rank c < rank r then "less optimistic"
           else "different"
         in
         let origin =
           if o != memexec && find memexec = c then ", as with memexec" else ""
         in
         Some (key, string_of_status c, string_of_status r, verdict, origin))
    keys

(* The same, printed. *)
let differing_statuses keys ~reference ~memexec o =
  List.map
    (fun (key, c, r, verdict, origin) ->
       Format.sprintf "  %s: %s against %s: %s%s" key c r verdict origin)
    (status_differences keys ~reference ~memexec o)

(* The outputs of the passes, in the summary. *)
let record_outputs ~reference ~memexec ~current =
  let keys =
    List.sort_uniq compare
      (List.map fst reference.statuses @ List.map fst current.statuses
       @ List.map fst memexec.statuses)
  in
  record [ "properties"; string_of_int (List.length keys) ];
  List.iter
    (fun (run, o) ->
       List.iter
         (fun (key, c, r, verdict, origin) ->
            record [ "status"; run; key; c; r; verdict;
                     String.trim (Str.global_replace (Str.regexp "^, ") ""
                                    origin) ])
         (status_differences keys ~reference ~memexec o))
    [ "recording", current; "memexec", memexec ];
  let only a b = List.filter (fun x -> not (List.mem x b)) a in
  List.iter
    (fun (run, o) ->
       let print (alarm, status) =
         alarm ^ ": " ^ Description.status_feedback status
       in
       record [ "alarms"; run; string_of_int (List.length o.alarms) ];
       List.iter (fun a -> record [ "alarm"; run; "missing"; print a ])
         (only reference.alarms o.alarms);
       List.iter (fun a -> record [ "alarm"; run; "added"; print a ])
         (only o.alarms reference.alarms))
    [ "reference", reference; "recording", current; "memexec", memexec ];
  List.iter
    (fun (run, o) ->
       let stmts, funs, alarms = o.statistics in
       record [ "statistics"; run; Format.sprintf "%.4f" stmts;
                Format.sprintf "%.4f" funs; string_of_int alarms ])
    [ "reference", reference; "recording", current; "memexec", memexec ];
  (* The blocks created by an analysis are named in each project with its own
     suffix of a counter, which is removed for a second comparison, with the
     spaces and the line breaks that align the names. *)
  let without_suffixes text =
    Str.global_replace (Str.regexp "\\(_[0-9]+\\)+\\([^A-Za-z0-9_]\\|$\\)")
      "\\2" text
    |> Str.global_replace (Str.regexp "[ \n]+") " "
  in
  List.iter
    (fun (run, o) ->
       record [ "messages"; run;
                if String.equal o.output reference.output then "equal"
                else if String.equal (without_suffixes o.output)
                    (without_suffixes reference.output)
                then "equal up to the suffixes of the names"
                else "differ" ])
    [ "recording", current; "memexec", memexec ]

(* Prints the messages [output] in a box, one line per line. *)
let print_messages title output =
  Format.printf "@[<v 2>%s:" title;
  List.iter (Format.printf "@ %s")
    (String.split_on_char '\n' (String.trim output));
  Format.printf "@]@."

let print_outputs ~reference ~memexec ~current =
  let keys =
    List.sort_uniq compare
      (List.map fst reference.statuses @ List.map fst current.statuses
       @ List.map fst memexec.statuses)
  in
  begin match differing_statuses keys ~reference ~memexec current with
    | [] ->
      Format.printf "Statuses of the properties: those of the run without \
                     memexec, for %s.@."
        (plural ~plural:"properties" (List.length keys) "property")
    | lines ->
      Format.printf "Statuses of the properties that differ from the run \
                     without memexec:@.";
      List.iter (Format.printf "%s@.") lines
  end;
  begin match differing_statuses keys ~reference ~memexec memexec with
    | [] -> ()
    | lines ->
      Format.printf "Statuses with memexec, without recording, that differ \
                     from the run without memexec:@.";
      List.iter (Format.printf "%s@.") lines
  end;
  let kept o =
    List.filter (fun (_, status) -> rank (Some status) < 2) o.alarms
  in
  if reference.alarms = current.alarms then
    Format.printf "Alarms: %d, of which %d not proven, those of the run \
                   without memexec.@."
      (List.length current.alarms) (List.length (kept current))
  else begin
    let print (alarm, status) =
      Format.sprintf "%s: %s" alarm (Description.status_feedback status)
    in
    let only a b = List.filter (fun x -> not (List.mem x b)) a in
    Format.printf "Alarms that differ from the run without memexec:@.";
    List.iter (fun a -> Format.printf "  missing: %s@." (print a))
      (only reference.alarms current.alarms);
    List.iter (fun a -> Format.printf "  added: %s@." (print a))
      (only current.alarms reference.alarms)
  end;
  let print_statistics (stmts, funs, alarms) =
    Format.sprintf "statement coverage %.4f, function coverage %.4f, %s"
      stmts funs (plural alarms "alarm")
  in
  if reference.statistics = current.statistics then
    Format.printf "Summary: %s, those of the run without memexec.@."
      (print_statistics current.statistics)
  else
    Format.printf "Summary: %s, against %s without memexec%s.@."
      (print_statistics current.statistics)
      (print_statistics reference.statistics)
      (if memexec.statistics = current.statistics then ", as with memexec"
       else "");
  if reference.output <> "" || current.output <> "" then begin
    print_messages "Messages of the passes, run without memexec"
      reference.output;
    if memexec.output <> reference.output then
      print_messages
        "Messages of the passes with memexec, without recording, which \
         differ from the run without memexec"
        memexec.output;
    if reference.output = current.output then
      Format.printf "Messages of the passes with -eva-hit-log: those of the \
                     run without memexec.@."
    else
      print_messages
        ("Messages of the passes with -eva-hit-log, which differ from the \
          run without memexec"
         ^ if memexec.output = current.output then ", as with memexec" else "")
        current.output
  end

(* ----- Main -------------------------------------------------------------- *)

(* Analyses a copy of the current project, made before its analysis. The
   option -eva is set, as for the current project, so that the passes after
   the iteration print the values at the end of each function. *)
let copy_and_analyse name ~memexec =
  let project = Project.create_by_copy ~last:false name in
  record [ "phase"; name ];
  let passes =
    Project.on project
      (fun () ->
         Parameters.Memexec.set memexec;
         Parameters.HitLog.off ();
         Parameters.Eva.on ();
         analyse ())
      ()
  in
  project, passes

(* The statements and functions of each project are its own: the points are
   built in each project, in the same order. *)
let in_project project f = Project.on project (fun () -> f (points ())) ()

(* Makes the requests of [f] in the current project, with the trap on, and
   returns their result with the requests reported. *)
let with_trap f =
  Legacy_read_trap.start ();
  checking := true;
  let result = f () in
  checking := false;
  Legacy_read_trap.stop ();
  result, Legacy_read_trap.requests ()

(* The summary of what main prints, but the outputs of the passes. *)
let record_summary ~below ~different_stacks ~different_filtered ~compared
    ~reported ~memexec_passes ~current_passes =
  let n kind = List.length (List.filter (fun (_, _, k) -> kind k) !calls) in
  record [ "calls";
           string_of_int (n (function Analysed _ -> true | _ -> false));
           string_of_int (n (function Hit _ -> true | _ -> false));
           string_of_int (n (( = ) (Other "specification")));
           string_of_int (n (( = ) (Other "builtin")));
           string_of_int (List.length below) ];
  Hashtbl.fold (fun (point, what) n acc -> (point, what, n) :: acc)
    made_by_kind []
  |> List.sort compare
  |> List.iter (fun (point, what, n) ->
      record [ "requests"; point; what; string_of_int n ]);
  List.iter
    (fun (run, table) ->
       let get v = Option.value ~default:0 (Hashtbl.find_opt table v) in
       record ("verdicts" :: run ::
               List.map (fun v -> string_of_int (get v))
                 [ Equal; Covers; More_precise; Omits; Unavailable ]))
    [ "recording", counts; "memexec", memexec_counts ];
  let total = string_of_int (List.length compared) in
  record [ "callstacks"; string_of_int (List.length different_stacks); total ];
  record [ "callstacks filtered";
           string_of_int (List.length different_filtered); total ];
  record [ "trap"; string_of_int !made; string_of_int (List.length reported);
           (if !unmatched = [] then "matched" else "unmatched");
           string_of_int
             (List.length
                (List.concat_map (fun r -> r.Legacy_read_trap.reads)
                   reported)) ];
  List.iter
    (fun (run, passes) ->
       record [ "passes"; run; string_of_int (List.length passes.requests);
                string_of_int (reads_of passes);
                string_of_int (List.length passes.strays) ])
    [ "memexec", memexec_passes; "recording", current_passes ];
  List.iter (fun (name, n) -> record [ "pass"; name; string_of_int n ])
    (by_pass current_passes);
  let on_below r =
    List.exists
      (fun cs ->
         String.ends_with ~suffix:("; callstack " ^ cs)
           r.Legacy_read_trap.description)
      below
  in
  record [ "below requests";
           string_of_int
             (List.length (List.filter on_below current_passes.requests)) ]

let observe () =
  let current = Project.current () in
  collect_existing_variables ();
  let reference, reference_passes =
    copy_and_analyse "reference" ~memexec:false
  in
  let with_memexec, memexec_passes = copy_and_analyse "memexec" ~memexec:true in
  record [ "phase"; "recording" ];
  Parameters.Eva.on ();
  observing_calls := true;
  let current_passes = analyse () in
  observing_calls := false;
  print_calls ();
  if not (Analysis.is_computed ()) then begin
    record [ "no result" ];
    Format.printf "The analysis with -eva-hit-log has no result: no request \
                   is made.@."
  end
  else begin
    record [ "phase"; "requests" ];
    if suite then
      without_body := Project.on reference called_without_body ();
    (* The callstacks at each point, in the three projects, then the answers
       for the callstacks of the three projects. *)
    let callstacks_in project = in_project project (List.map callstacks) in
    let reference_stacks = callstacks_in reference in
    let memexec_stacks = callstacks_in with_memexec in
    assert (Project.equal current (Project.current ()));
    let current_stacks, reported_stacks =
      with_trap (fun () -> callstacks_in current)
    in
    let starts =
      List.combine (points ()) current_stacks
      |> List.filter_map
        (fun (point, stacks) ->
           if String.starts_with ~prefix:"start of " point.trap
           then Some stacks else None)
    in
    let below = print_below starts in
    (* The callstacks listed with the recording are compared with those of
       the run without memexec before their union is taken: a callstack that
       one of the two lacks is not hidden by the requests made on the union. *)
    let different_stacks =
      List.combine (points ()) (List.combine reference_stacks current_stacks)
      |> List.filter_map
        (fun (point, (r, c)) ->
           if List.map snd r = List.map snd c then None
           else Some point.description)
    in
    let stacks =
      List.map2 (fun (r, m) c -> union [ r; m; c ])
        (List.combine reference_stacks memexec_stacks) current_stacks
    in
    let answers_in project =
      in_project project (fun points -> List.map2 answers points stacks)
    in
    let reference_answers = answers_in reference in
    let memexec_answers = answers_in with_memexec in
    let answers, reported_answers =
      with_trap (fun () -> answers_in current)
    in
    let reported = reported_stacks @ reported_answers in
    let reference_answers = rename ~into:answers reference_answers in
    let memexec_answers = rename ~into:answers memexec_answers in
    let compared =
      List.map2
        (fun (reference, memexec) current -> { reference; memexec; current })
        (List.combine reference_answers memexec_answers) answers
    in
    let compared = List.combine (points ()) compared in
    List.iter print_labelled compared;
    print_control compared;
    let initial = snd (List.hd compared) in
    Format.printf "Initial state: %s.@."
      (string_of_verdict
         (verdict ~reference:initial.reference.joined
            ~answer:initial.current.joined));
    Format.printf "Differences with the run without memexec:@.";
    List.iter2
      (fun (point, c) listed ->
         compare_point point c ~listed:(List.map snd listed))
      compared current_stacks;
    let get v = Option.value ~default:0 (Hashtbl.find_opt counts v) in
    Format.printf "Answers: %d equal, %d covering, %d more precise, \
                   %d omitting, %d unavailable.@."
      (get Equal) (get Covers) (get More_precise) (get Omits) (get Unavailable);
    let reads = List.concat_map (fun r -> r.Legacy_read_trap.reads) reported in
    let different_filtered =
      List.filter_map
        (fun (point, c) ->
           if c.reference.filtered_stacks = c.current.filtered_stacks then None
           else Some point.description)
        compared
    in
    let print_different what = function
      | [] ->
        Format.printf "Callstacks listed%s: those of the run without memexec \
                       at each of the %d points.@."
          what (List.length compared)
      | list ->
        Format.printf "@[<v 2>Callstacks listed%s: NOT those of the run \
                       without memexec at %d of the %d points:"
          what (List.length list) (List.length compared);
        List.iter (Format.printf "@ %s") list;
        Format.printf "@]@."
    in
    print_different "" different_stacks;
    print_different " through the filter" different_filtered;
    Format.printf "Filtered requests that reject one callstack: %d.@."
      !rejecting;
    Format.printf "Requests made: %d; reported by the trap: %d, %s; reads of \
                   the legacy store: %d.@."
      !made (List.length reported)
      (if !unmatched = [] then "each once with its description"
       else "NOT each once with its description")
      (List.length reads);
    List.iter
      (fun (expected, added) ->
         Format.printf "  @[<v 2>request %s, reported as:%t@]@." expected
           (fun fmt -> match added with
              | [] -> Format.fprintf fmt "@ nothing"
              | _ -> List.iter (Format.fprintf fmt "@ %s") added))
      (List.rev !unmatched);
    List.iter
      (fun r -> if r.Legacy_read_trap.reads <> [] then
          Format.printf "%a@." Legacy_read_trap.pretty_request r)
      reported;
    print_passes ~memexec:memexec_passes ~current:current_passes ~below;
    let reference = outputs reference reference_passes
    and memexec = outputs with_memexec memexec_passes
    and current = outputs current current_passes in
    print_outputs ~reference ~memexec ~current;
    if suite then begin
      record [ "initial";
               string_of_verdict
                 (verdict ~reference:initial.reference.joined
                    ~answer:initial.current.joined) ];
      record_summary ~below ~different_stacks ~different_filtered ~compared
        ~reported ~memexec_passes ~current_passes;
      record_outputs ~reference ~memexec ~current
    end
  end;
  record [ "phase"; "done" ]

let main () =
  if suite && Analysis.is_computed () then begin
    record [ "error"; "the analysis is computed before the observer starts" ];
    Format.printf "The analysis is computed before the observer starts: no \
                   observation.@."
  end
  else observe ()

let () = Boot.Main.extend main
