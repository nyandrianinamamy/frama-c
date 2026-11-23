(* Observer of the tests of option -eva-hit-log.

   The current project is analysed with the options of the test, which set
   -eva-hit-log. Two copies of it, made before, are analysed without
   recording: the reference, without memexec, and a run with memexec. After
   the analyses, the observer asks Eva.Results, in each project, for the
   callstacks that reach the start of each function and the points before and
   after each statement, then for the state at each of these points: joined
   over the callstacks, through a filter that rejects the first callstack of
   the reference when the reference lists several, and for each callstack
   that reaches the point in one of the three projects.

   The run with memexec and without recording is compared with the reference
   between these two runs only: on the callstacks that one of the two lists,
   with the allocated blocks of the two matched to each other. Its verdicts
   do not depend on the run with -eva-hit-log.

   It prints:
   - the calls of the analysis with -eva-hit-log, with the cache entry they
     compute or use;
   - when this analysis calls a builtin that allocates or frees a block, or
     Eva counts a heap call, the number of heap calls of each function and
     the number of hits that memexec does not make because it does not
     store them, as Eva counts them in its statistics (see
     print_heap_calls);
   - the callstacks that reach the start of a function in the current project
     and are not those of a call of the analysis: the calls below a hit,
     whose body did not run;
   - the calls below a hit that the observer rebuilds from the calls made by
     the analysed call of each cache entry, if they differ from those that
     Eva lists, and those of them that cross a recursion, if any;
   - the statements where Eva.Results.is_reachable differs from the test of
     the joined state before them against bottom, with -eva-hit-log, if any
     (see check_reachability);
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
     "unavailable": the answer is top, as for a function without results;
     "unresolved": the answer or the reference holds an allocated block
     whose match in the other run is not decided, or that is a summary of
     several blocks in the reference and one block in the answer, or
     whose validity differs in extent.
     An answer that holds a summary of several blocks matched to one block
     of the reference is compared in one direction only: it covers the
     reference or omits it.
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
   computed before it starts. What it prints is otherwise unchanged. When
   the environment variable HIT_LOG_OBSERVER_REACHABILITY names a file, the
   observer appends to it the number of statements where it compared
   Eva.Results.is_reachable with the joined state (see check_reachability).
   The
   environment variables HIT_LOG_OBSERVER_STAGE and HIT_LOG_OBSERVER_STAGES
   select the stage of the command line that it observes, and list the
   stages that start an analysis, for that script too.

   Three other environment variables are controls, for the tests of the
   observer itself: they make a run differ from what Eva gives, in a known
   way, to check what the observer concludes. See "Controls" below. *)

open Eva

(* ----- Summary ----------------------------------------------------------- *)

let summary =
  match Sys.getenv_opt "HIT_LOG_OBSERVER_SUMMARY" with
  | None | Some "" -> None
  | Some file -> Some (open_out file)

let suite = Option.is_some summary

(* The version of the records of the summary, which dev/hit-log-suite.py
   checks before it reads them. *)
let format = "3"

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

(* The first record, written when the observer is loaded: a summary without
   it is not one of this observer. *)
let () = record [ "format"; format ]

(* ----- Controls ---------------------------------------------------------- *)

(* For the tests of the observer itself, three environment variables make a
   run differ, in a known way, from what the command line asks or from what
   Eva gives, so that the conclusions of the observer are checked on a
   difference. A control is printed, and recorded in the summary: a run
   under a control is not an observation of Eva. The variables:
   - HIT_LOG_OBSERVER_ALLOC_REFERENCE and HIT_LOG_OBSERVER_ALLOC_MEMEXEC give
     the value of -eva-alloc-builtin in the run without memexec, and in the
     run with memexec and without recording;
   - HIT_LOG_OBSERVER_UNAVAILABLE names a label. At the points before and
     after the statement that has it, the observer takes as listed with
     -eva-hit-log the callstacks that reach the start of the function, and
     as unavailable each answer with -eva-hit-log, as if Eva gave them. *)
let control variable =
  match Sys.getenv_opt variable with
  | None | Some "" -> None
  | Some value -> Some value

let alloc_controls =
  [ "reference", control "HIT_LOG_OBSERVER_ALLOC_REFERENCE";
    "memexec", control "HIT_LOG_OBSERVER_ALLOC_MEMEXEC" ]

let unavailable_control = control "HIT_LOG_OBSERVER_UNAVAILABLE"

let print_controls () =
  let print what value =
    Format.printf "Control: %s %s.@." what value;
    record [ "control"; what; value ]
  in
  List.iter
    (fun (run, title) ->
       Option.iter
         (print
            (Format.sprintf "the run %s allocates with -eva-alloc-builtin"
               title))
         (List.assoc run alloc_controls))
    [ "reference", "without memexec";
      "memexec", "with memexec, without recording" ];
  Option.iter
    (print "the answers with -eva-hit-log are taken as unavailable, on the \
            callstacks of the start of the function, at the statement \
            labelled")
    unavailable_control

(* ----- Stages of the command line ---------------------------------------- *)

(* The observer acts at each stage of the command line, as in the ptests
   rules, or at the stage numbered by the environment variable
   HIT_LOG_OBSERVER_STAGE only, the first being 1: dev/hit-log-suite.py
   observes in this way an analysis that a later stage starts. *)
let selected_stage =
  match Sys.getenv_opt "HIT_LOG_OBSERVER_STAGE" with
  | None | Some "" -> None
  | Some n -> Some (int_of_string n)

(* When the environment variable HIT_LOG_OBSERVER_STAGES names a file, the
   observer only writes there one record per stage: its number, the project
   it runs on, and the projects in which an analysis of Eva started during
   the stage. dev/hit-log-suite.py finds in this way the stages of a test
   that start an analysis. A stage that the command does not finish is
   written at exit, marked as such. *)
let stages =
  match Sys.getenv_opt "HIT_LOG_OBSERVER_STAGES" with
  | None | Some "" -> None
  | Some file -> Some (open_out file)

let stage = ref 0
let started_in_stage = ref []

let write_stage ?(unfinished=false) channel =
  output_string channel
    (String.concat "\t"
       ([ "stage"; string_of_int !stage;
          Project.get_name (Project.current ());
          String.concat "," (List.rev !started_in_stage) ]
        @ if unfinished then [ "unfinished" ] else []));
  output_char channel '\n';
  flush channel;
  started_in_stage := []

let () =
  Option.iter
    (fun channel ->
       Analysis.register_computation_hook ~on:Computing
         (fun _ ->
            started_in_stage :=
              Project.get_name (Project.current ()) :: !started_in_stage);
       at_exit
         (fun () ->
            if !started_in_stage <> [] then begin
              incr stage;
              write_stage ~unfinished:true channel
            end))
    stages

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

(* The calls made by each call in progress, by its callstack: the callstack
   of the call made and how it was analysed, most recent first. A call on a
   callstack ends before another call on that callstack starts, but for an
   interrupted call, which never ends: the calls in progress on a callstack
   are kept as a stack, by Hashtbl.add and Hashtbl.remove. *)
let made_by_calls_in_progress = Hashtbl.create 17

(* The calls made by the analysed call of each cache entry, by number of the
   entry: the calls made at each call statement of its body while it ran,
   which are those its cache entry keeps. Two calls on one callstack can
   compute two cache entries that make different calls. *)
let made_by_entry = Hashtbl.create 17

(* The statements that the analysed call of each cache entry reaches, by
   number of the entry: those with a state before them, and those with a
   state after them. *)
let reached_by_entry = Hashtbl.create 17

let reached (states : Cvalue_callbacks.results) =
  let reached table =
    Cil_datatype.Stmt.Hashtbl.fold
      (fun stmt state acc ->
         if Cvalue.Model.is_reachable state
         then Cil_datatype.Stmt.Set.add stmt acc else acc)
      (Lazy.force table) Cil_datatype.Stmt.Set.empty
  in
  reached states.before_stmts, reached states.after_stmts

let () =
  Cvalue_callbacks.register_call_hook
    (fun callstack kf _state _kind ->
       if !observing_calls then begin
         started := (portable callstack, kf) :: !started;
         events := Start (portable callstack) :: !events;
         Hashtbl.add made_by_calls_in_progress (portable callstack) (ref [])
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
       if !observing_calls then begin
         let kind =
           match results with
           | `Body (_, id) -> Analysed id
           | `Reuse id -> Hit id
           | `Spec _ -> Other "specification"
           | `Builtin _ -> Other "builtin"
         in
         calls := (identify callstack, kf, kind) :: !calls;
         let p = portable callstack in
         let made =
           match Hashtbl.find_opt made_by_calls_in_progress p with
           | None -> []
           | Some made ->
             Hashtbl.remove made_by_calls_in_progress p;
             List.rev !made
         in
         begin match results with
           | `Body (states, id) ->
             Hashtbl.replace made_by_entry id made;
             Hashtbl.replace reached_by_entry id (reached states)
           | `Reuse _ | `Spec _ | `Builtin _ -> ()
         end;
         match p.calls with
         | call :: calls ->
           Option.iter
             (fun made -> made := (call, kind) :: !made)
             (Hashtbl.find_opt made_by_calls_in_progress { p with calls })
         | [] -> ()
       end)

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

(* The statistics that Eva keeps per function with -eva-hit-log, in this
   order: the calls analysed by their body that are heap calls, whose cache
   entries hold full states and that memexec does not store; the calls
   analysed by their body that memexec would have answered from the cache
   entry of a heap call, had it stored them; and among the latter, those
   made during the analysis of another one, which a hit would not have
   analysed. They are found by name: a statistic that Eva does not keep
   reads 0. Statistics are kept with each project, and are read in the
   project with -eva-hit-log once its analysis has ended. *)
let heap_statistics =
  List.map
    (fun name -> Statistics.register_function_stat name Statistics.Int)
    [ "hit-log-heap-calls"; "hit-log-lost-hits"; "hit-log-lost-hits-below" ]

(* The functions of the builtins that allocate or free a block. *)
let allocation_builtins =
  [ "malloc"; "calloc"; "realloc"; "reallocarray"; "alloca"; "free";
    "__fc_vla_alloc"; "__fc_vla_free" ]

(* Prints the counts of [heap_statistics] per function, when one is not
   zero or when the analysis with -eva-hit-log called one of
   [allocation_builtins]. Records their totals in the summary. *)
let print_heap_calls () =
  let counts stat =
    Globals.Functions.fold
      (fun kf acc ->
         match Statistics.get stat kf with
         | 0 -> acc
         | n -> (Kernel_function.get_name kf, n) :: acc)
      []
    |> List.sort compare
  in
  let heap, lost, lost_below =
    match List.map counts heap_statistics with
    | [ heap; lost; lost_below ] -> heap, lost, lost_below
    | _ -> assert false
  in
  let allocates =
    List.exists
      (fun (_, kf, kind) ->
         kind = Other "builtin"
         && List.mem (Kernel_function.get_name kf) allocation_builtins)
      !calls
  in
  let pp_counts fmt = function
    | [] -> Format.pp_print_string fmt "none"
    | counts ->
      Format.pp_print_list
        ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
        (fun fmt (name, n) -> Format.fprintf fmt "%s %d" name n)
        fmt counts
  in
  if allocates || heap <> [] || lost <> [] || lost_below <> [] then begin
    Format.printf "@[<hov 2>Heap calls, with full states, not stored by \
                   memexec:@ %a.@]@." pp_counts heap;
    Format.printf "@[<hov 2>Hits not made, the heap calls being not \
                   stored:@ %a.@]@." pp_counts lost;
    if lost_below <> [] then
      Format.printf "@[<hov 2>Hits not made during the analysis of a call \
                     that would have been a hit:@ %a.@]@." pp_counts lost_below
  end;
  let total counts = List.fold_left (fun acc (_, n) -> acc + n) 0 counts in
  record ("heap calls" ::
          List.map (fun l -> string_of_int (total l)) [ heap; lost; lost_below ])

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
  below

(* ----- Points ------------------------------------------------------------ *)

type point = {
  description: string;
  request: Results.request;
  trap: string; (* The point, as Eva.Legacy_read_trap describes it. *)
  kf: Kernel_function.t option; (* The function of the point. *)
  show: bool; (* Whether its states are printed. *)
  kind: string; (* The kind of point, for the summary. *)
  stmt: Cil_types.stmt option; (* The statement of a point before or after
                                  a statement. *)
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
        kf = Some kf; show = labelled; kind = "start"; stmt = None }
    in
    let of_stmt stmt =
      [ { description = describe_stmt "before" stmt;
          request = Results.before stmt; trap = trap_stmt "before" stmt;
          kf = Some kf; show = labelled && labels stmt <> [];
          kind = "before"; stmt = Some stmt };
        { description = describe_stmt "after" stmt;
          request = Results.after stmt; trap = trap_stmt "after" stmt;
          kf = Some kf;
          show = labelled && Cil_datatype.Stmt.equal stmt return;
          kind = "after"; stmt = Some stmt } ]
    in
    start :: List.concat_map of_stmt stmts
  in
  let of_declaration name =
    let kf = Globals.Functions.find_by_name name in
    { description = name ^ ", start, without body";
      request = Results.at_start_of kf; trap = "start of " ^ name;
      kf = Some kf; show = false; kind = "start without body"; stmt = None }
  in
  let main = fst (Globals.entry_point ()) in
  (* An entry point without a body has no final state. *)
  let final =
    match Kernel_function.find_return main with
    | return ->
      [ { description = "final state"; request = Results.at_end ();
          trap = trap_stmt "after" return;
          kf = None; show = false; kind = "final"; stmt = None } ]
    | exception Kernel_function.No_Statement -> []
  in
  { description = "initial state"; request = Results.at_start;
    trap = "initial state"; kf = None; show = false; kind = "initial";
    stmt = None }
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

(* The answers at [point], for the callstacks [stacks]. When the run
   without memexec lists several callstacks at [point], [in_reference], the
   filter rejects the first of them, in the three projects: a callstack that
   another project lists alone does not change the filter. *)
let answers (point : point) ~in_reference stacks =
  let state ~what ~expected request_ =
    request ~point:point.kind ~what ~expected
      (fun () -> Results.get_cvalue_model_result request_)
  in
  let joined =
    state ~what:"joined" ~expected:(point.trap ^ "; joined") point.request
  in
  let keep =
    match in_reference with
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


(* ----- Allocated blocks -------------------------------------------------- *)

(* The bases of allocated blocks, and the variables that Eva creates during
   the analysis, as those of the context of option -lib-entry and the copies
   of the locals of recursive calls, are created by each analysis, with
   another identity in each project, and sometimes with a counter shared by
   the projects in their name. The variables that exist before the analyses
   have the same identity in the three projects, which are copies. The
   created bases are matched across projects by a key:
   - an allocated block, by the callstack of the call of an allocation
     built-in that created it, which ends with its call statement, and by
     the number of the blocks created before it on this callstack, as with
     -eva-alloc-builtin fresh: its name tells neither the call statement
     nor the callstack, and a block made weak is renamed;
   - another created variable, by its name without the suffixes of the
     counter, and by the location of its declaration: a copy of a variable
     of a recursive call has the location of the variable. *)

(* A created base is unresolved when its key is that of several bases in
   one of the two projects, when its callstack creates a different number of
   blocks in the two projects, or when it matches no base while a base of
   the other project that matches none has the same name, a weak block being
   named as a strong one. *)

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

(* The run whose analysis is in progress: "reference", "memexec" or
   "recording". *)
let analysing = ref None

(* For each run, the allocated blocks that the allocation built-ins create:
   for each block, the callstack of the call that created it and the number
   of the blocks created before it on this callstack; and the number of the
   blocks created on each callstack. A call creates the allocated blocks
   that the states at the end of the built-in bind, and that no earlier call
   of the run bound. *)
type allocations = {
  origins: (portable * int) Base.Hashtbl.t;
  by_site: (portable, int) Hashtbl.t;
}

let allocations = Hashtbl.create 3

let allocations_of run =
  match Hashtbl.find_opt allocations run with
  | Some a -> a
  | None ->
    let a = { origins = Base.Hashtbl.create 7; by_site = Hashtbl.create 7 } in
    Hashtbl.replace allocations run a;
    a

let () =
  Cvalue_callbacks.register_call_results_hook
    (fun callstack _kf _state results ->
       match !analysing, results with
       | Some run, `Builtin (states, _) ->
         let a = allocations_of run in
         let add acc = function
           | Cvalue.Model.Map map ->
             Cvalue.Model.fold
               (fun base _ acc ->
                  match base with
                  | Base.Allocated _ when not (Base.Hashtbl.mem a.origins base)
                    -> Base.Hptset.add base acc
                  | _ -> acc)
               map acc
           | Cvalue.Model.Bottom | Cvalue.Model.Top -> acc
         in
         let site = portable callstack in
         List.fold_left add Base.Hptset.empty states
         |> Base.Hptset.elements
         |> List.sort (fun b b' -> Int.compare (Base.id b) (Base.id b'))
         |> List.iter
           (fun base ->
              let n =
                Option.value ~default:0 (Hashtbl.find_opt a.by_site site)
              in
              Base.Hashtbl.replace a.origins base (site, n);
              Hashtbl.replace a.by_site site (n + 1))
       | _, (`Builtin _ | `Spec _ | `Body _ | `Reuse _) -> ())

(* Fold over bindings and pointer values. A zero-sized block may occur
   only in a value. *)
let fold_bases_of_answer add_base acc answer =
  let add_value v acc =
    try Cvalue.V.fold_bases add_base (Cvalue.V_Or_Uninitialized.get_v v) acc
    with Abstract_interp.Error_Top -> acc
  in
  match answer with
  | Ok (Cvalue.Model.Map map) ->
    Cvalue.Model.fold
      (fun base offsetmap acc ->
         add_base base acc
         |> Cvalue.V_Offsetmap.fold_on_values add_value offsetmap)
      map acc
  | _ -> acc

(* The created bases of [answers]. *)
let allocated_bases answers =
  let add base acc =
    if created_by_analysis base then Base.Set.add base acc else acc
  in
  List.fold_left
    (fun acc a ->
       List.fold_left (fold_bases_of_answer add) acc
         (a.joined :: a.filtered :: List.map snd a.by_callstack))
    Base.Set.empty answers

type key =
  | Site of portable * int (* An allocated block, by its creation. *)
  | Named of string * string (* Another base, by its name and location. *)

let counter_suffix = Str.regexp "\\(_[0-9]+\\)+$"

let name base = (Base.to_varinfo base).vname

let stripped base = Str.global_replace counter_suffix "" (name base)

(* The name of a base, as that of a strong block if it is a weak one. *)
let family base =
  Str.global_replace (Str.regexp_string "_w_") "_" (stripped base)

let key run base =
  match Base.Hashtbl.find_opt (allocations_of run).origins base with
  | Some (site, n) -> Site (site, n)
  | None ->
    let vi = Base.to_varinfo base in
    Named (stripped base, Format.asprintf "%a" Fileloc.pretty vi.vdecl)

(* Capture mutable validity fields and names while the owning project is
   current. Only [base] itself is used for identity and substitution later. *)
type block = {
  base: Base.t;
  name: string;
  extent: [ `Variable of Z.t * Z.t * Z.t | `Fixed of Base.validity ];
  weak: bool;
}

let capture base =
  let extent = match Base.validity base with
    | Base.Variable v -> `Variable (v.min_alloc, v.max_alloc, v.max_allocable)
    | v -> `Fixed v
  in
  { base; name = name base; extent; weak = Base.is_weak base }

let describe block =
  let extent = match block.extent with
    | `Variable (lo, hi, limit) ->
      Format.asprintf "Variable [0..%a--%a], max allocable %a"
        Z.pretty lo Z.pretty hi Z.pretty limit
    | `Fixed v -> Format.asprintf "%a" Base.pretty_validity v
  in
  Format.asprintf "%s (%s, %s)" block.name extent
    (if block.weak then "weak" else "strong")

let created run answers =
  let blocks =
    Base.Hashtbl.fold
      (fun base _ acc -> Base.Set.add base acc)
      (allocations_of run).origins (allocated_bases answers)
    |> Base.Set.elements
    |> List.map (fun base -> key run base, family base, capture base)
  in
  run, blocks

(* The created bases of the run [source], each with its key, matched to
   those of the run [target]: the pairs of the bases matched, and the bases
   of the two runs that are unresolved. *)
let matching (source_run, source) (target_run, target) =
  let unresolved = ref [] in
  let mark block = unresolved := block :: !unresolved in
  let created_on run site =
    Option.value ~default:0 (Hashtbl.find_opt (allocations_of run).by_site site)
  in
  let site_differs = function
    | Site (site, _) -> created_on source_run site <> created_on target_run site
    | Named _ -> false
  in
  let with_key key list = List.filter (fun (k, _, _) -> k = key) list in
  let mapped = ref [] and unmatched = ref [] in
  List.iter
    (fun (key, family, base) ->
       if site_differs key then mark base
       else
         match with_key key target with
         | [ _, _, base' ] when List.length (with_key key source) = 1 ->
           mapped := (base, base') :: !mapped
         | [] -> unmatched := (family, base) :: !unmatched
         | candidates ->
           mark base;
           List.iter (fun (_, _, base') -> mark base') candidates)
    source;
  List.iter (fun (key, _, base) -> if site_differs key then mark base) target;
  let same a b = Base.equal a.base b.base in
  let matched base = List.exists (fun (_, b) -> same b base) !mapped in
  let unmatched_target =
    List.filter
      (fun (_, _, base) ->
         not (matched base || List.exists (same base) !unresolved))
      target
  in
  List.iter
    (fun (family, base) ->
       let alike =
         List.filter (fun (_, f, _) -> String.equal f family) unmatched_target
       in
       if alike <> [] then begin
         mark base;
         List.iter (fun (_, _, base') -> mark base') alike
       end)
    !unmatched;
  !mapped, !unresolved

(* An allocated block is one block, a strong base, or a summary of the
   blocks allocated at one place, a weak base, which Eva updates weakly: a
   store adds its value to those that the base has. Eva makes a base weak in
   place, during the analysis: the strength compared here is that of the
   base at the end of its analysis. Renaming a base into its match loses its
   strength, so the pairs matched whose strengths differ are kept apart,
   as follows. Substitution also erases the extent. Require identical
   extents before comparing contents in the coordinates of the target.
   - a strong base matched to a weak base of the run compared with it: a
     state with the one block is among the states that the summary
     describes, with the same contents, and not the converse. Only the
     inclusion of the first run in the second is tested;
   - a weak base matched to a strong base of the run compared with it: the
     states that the summary describes are not all states of the one block.
     No inclusion is tested: the answers that hold it are unresolved. *)

(* How the created bases of a run, the source, are matched to those of the
   run it is compared with, the target:
   - [unresolved]: the bases of the two runs whose match is not decided,
     and the bases of the pairs matched whose source is weak and whose
     target is strong, or whose extents differ;
   - [summarised]: the weak bases of the target matched to a strong base of
     the source;
   - [names]: the names of the bases of the source that are matched, with
     the names of their match;
   - [undecided], [weaker], [summarising]: the same bases, by name, for
     their printing: the bases whose match is not decided, and pairs with
     differing extents printed source -> target, and strength pairs printed
     target first. *)
type matched = {
  unresolved: Base.Hptset.t;
  summarised: Base.Hptset.t;
  names: (string * string) list;
  unresolved_names: string list;
  undecided: string list;
  weaker: (string * string) list;
  summarising: (string * string) list;
}

let no_match =
  { unresolved = Base.Hptset.empty; summarised = Base.Hptset.empty;
    names = []; unresolved_names = []; undecided = [];
    weaker = []; summarising = [] }

(* The matches of the three comparisons: of the reference and of the run
   with memexec with the run with -eva-hit-log, and of the reference with
   the run with memexec. *)
let matched_reference = ref no_match
let matched_memexec = ref no_match
let matched_pair = ref no_match

(* Rename [answers] using the two runs' captured blocks. The target's
   project must be current for pointer substitution and normalization. *)
let rename ~source ~target answers =
  let mapped, undecided = matching source target in
  let mapped, different_extents =
    List.partition (fun (a, b) -> a.extent = b.extent) mapped
  in
  let weaker =
    List.filter (fun (a, b) -> a.weak && not b.weak) mapped
  and summarising =
    List.filter (fun (a, b) -> not a.weak && b.weak) mapped
  in
  let unresolved =
    List.fold_left (fun blocks (a, b) -> a :: b :: blocks)
      undecided (different_extents @ weaker)
  in
  let base_set blocks =
    List.fold_left (fun set b -> Base.Hptset.add b.base set)
      Base.Hptset.empty blocks
  and names blocks = List.map (fun b -> b.name) blocks in
  let names_of pairs =
    List.map (fun (a, b) -> b.name, a.name) pairs |> List.sort_uniq compare
  in
  let matched =
    { unresolved = base_set unresolved;
      summarised = base_set (List.map snd summarising);
      unresolved_names = names unresolved;
      names = List.map (fun (a, b) -> a.name, b.name) mapped;
      undecided = (
        let extents = List.map
            (fun (a, b) -> describe a ^ " -> " ^ describe b) different_extents
        in
        List.sort_uniq String.compare (extents @ names undecided));
      weaker = names_of weaker;
      summarising = names_of summarising }
  in
  let substitution =
    Base.substitution_from_list (List.map (fun (a, b) -> a.base, b.base) mapped)
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
  let renamed =
    List.map
      (fun a ->
         { joined = rename_answer a.joined;
           filtered = rename_answer a.filtered;
           by_callstack =
             List.map (fun (cs, a) -> cs, rename_answer a) a.by_callstack;
           filtered_stacks = a.filtered_stacks })
      answers
  in
  renamed, matched

(* Prints and records, for each of the three comparisons, the created bases
   whose match is unresolved and those that summarise a block of the run
   they are compared with, if any. *)
let print_matches () =
  let print (of_run, run, label, matched) =
    if matched.undecided <> [] || matched.weaker <> [] then begin
      Format.printf "@[<v 2>Created bases%s whose match with the run %s is \
                     unresolved:" of_run run;
      List.iter (Format.printf "@ %s") matched.undecided;
      List.iter
        (fun (name, name') ->
           Format.printf "@ %s, one block, for %s, a summary of several"
             name name')
        matched.weaker;
      Format.printf "@]@.";
      List.iter
        (fun name -> record [ "unresolved"; label; name; "match undecided" ])
        matched.undecided;
      List.iter
        (fun (name, name') ->
           record [ "unresolved"; label; name;
                    "one block, for the summary " ^ name' ])
        matched.weaker
    end;
    if matched.summarising <> [] then begin
      Format.printf "@[<v 2>Created bases%s that summarise several blocks, \
                     matched to one block of the run %s:" of_run run;
      List.iter
        (fun (name, name') -> Format.printf "@ %s, for %s" name name')
        matched.summarising;
      Format.printf "@]@.";
      List.iter
        (fun (name, name') -> record [ "summarised"; label; name; name' ])
        matched.summarising
    end
  in
  List.iter print
    [ "", "without memexec", "without memexec", !matched_reference;
      "", "with memexec", "with memexec", !matched_memexec;
      " of the run with memexec, without recording,", "without memexec",
      "memexec against reference", !matched_pair ]

(* Whether [answer] has a base of [bases]. *)
let mentions bases answer =
  not (Base.Hptset.is_empty bases)
  && fold_bases_of_answer
    (fun base found -> found || Base.Hptset.mem base bases) false answer

(* ----- Comparison -------------------------------------------------------- *)

type verdict = Equal | Covers | More_precise | Omits | Unavailable | Unresolved

(* The model of an answer, or None if it is unavailable. *)
let model = function
  | Ok Cvalue.Model.Top | Error (Results.Top | DisabledDomain) -> None
  | Ok state -> Some state
  | Error Results.Bottom -> Some Cvalue.Model.bottom

(* The verdict on [answer] against [reference], whose created bases are
   renamed by the match [matched], when both are available:
   - unresolved, if one of them has an unresolved base;
   - by the inclusion of the reference in the answer only, if one of them
     has a base that summarises a block of the reference: the answer covers
     the reference, or omits it when the reference is not included, and is
     never equal to it nor more precise;
   - by the two inclusions otherwise. *)
let verdict ?(matched = no_match) ~reference ~answer () =
  let has bases = mentions bases reference || mentions bases answer in
  match model reference, model answer with
  | _, None -> Unavailable
  | None, Some _ -> Omits
  | Some _, Some _ when has matched.unresolved -> Unresolved
  | Some reference, Some answer when has matched.summarised ->
    if Cvalue.Model.is_included reference answer then Covers else Omits
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
  | Unresolved -> "unresolved"

(* Renaming can merge adjacent pointer fragments based on the target
   block's strength. Inclusion can also construct default offsetmaps.
   Finish both operations in the memexec project before returning verdicts
   to the recording project. *)
type pair_verdicts = {
  joined_verdict: verdict;
  filtered_verdict: verdict;
  stack_verdicts: ((string * portable) * verdict) list;
}

let compare_pair project ~source ~target reference memexec stacks =
  Project.on project
    (fun () ->
       let reference, matched = rename ~source ~target reference in
       let compare reference answer = verdict ~matched ~reference ~answer () in
       let at_point (r, m) stacks =
         let stack_verdict cs =
           cs, compare (List.assoc cs r.by_callstack)
             (List.assoc cs m.by_callstack)
         in
         { joined_verdict = compare r.joined m.joined;
           filtered_verdict = compare r.filtered m.filtered;
           stack_verdicts = List.map stack_verdict stacks }
       in
       List.map2 at_point (List.combine reference memexec) stacks, matched)
    ()

(* The answers expressed in the recording project and the independent
   comparison of the reference with memexec. *)
type compared = {
  reference: point_answers;
  memexec: point_answers;
  current: point_answers;
  pair: pair_verdicts;
}

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
   recursion and with the cache entries of its counterparts, if they have
   one: from the hit down, one of its calls is a recursive call that
   renames variables, its function being already on the callstack of its
   caller, whether its counterpart was analysed by its body or by its
   specification. The counterpart of a call below a hit is the call made at
   the same statement by the analysed call of the cache entry that its
   caller uses. These callstacks are rebuilt from the calls of the analysis,
   from each hit down, as the rule of #87 does: the calls below a call that
   uses a cache entry are those made by the analysed call of this entry. A
   cache entry is completed after the entries its analysed call uses, so the
   rebuilding ends. *)
let crossing_callstacks =
  lazy begin
    let table = Hashtbl.create 17 in
    (* [walk q crossing id] adds the callstacks below the call on [q], which
       uses the cache entry [id] and does not run its body. *)
    let rec walk q crossing id =
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
           let previous, entries =
             Option.value ~default:(false, []) (Hashtbl.find_opt table p)
           in
           let entries =
             match entry with
             | Some id when not (List.mem id entries) -> id :: entries
             | _ -> entries
           in
           Hashtbl.replace table p (previous || crossing, entries);
           Option.iter (walk p crossing) entry)
        (Option.value ~default:[] (Hashtbl.find_opt made_by_entry id))
    in
    List.iter
      (fun ((_, p), _, kind) ->
         match kind with
         | Hit id -> walk p false id
         | Analysed _ | Other _ -> ())
      !calls;
    table
  end

let is_crossing table p =
  match Hashtbl.find_opt table p with
  | Some (crossing, _) -> crossing
  | None -> false

(* Whether one of the callstacks [stacks] is that of a call below a hit that
   crosses a recursion, and whose counterpart reaches [point] if it is before
   or after a statement: the rule keeps unreachable the points that the cache
   entry of the counterpart does not reach. *)
let crossing (point : point) stacks =
  let table = Lazy.force crossing_callstacks in
  let reaches id =
    match point.stmt, Hashtbl.find_opt reached_by_entry id with
    | None, _ -> true
    | Some _, None -> false
    | Some stmt, Some (before, after) ->
      Cil_datatype.Stmt.Set.mem stmt
        (if String.equal point.kind "before" then before else after)
  in
  List.exists
    (fun p ->
       match Hashtbl.find_opt table p with
       | Some (true, entries) ->
         Option.is_none point.stmt || List.exists reaches entries
       | Some (false, _) | None -> false)
    stacks

(* The name shown for a callstack of the current project that Eva may not
   list. *)
let display_portable p = display (string_of_callstack (rebuild p), p)

(* Prints the callstacks below a hit that the observer rebuilds and that Eva
   does not list among [listed], those that Eva lists and the observer does
   not rebuild, and those that cross a recursion. Only the callstacks of the
   functions [requested], whose start is requested, are compared and
   printed; those of the calls of the analysis are not below a hit. *)
let print_rebuilt ~listed ~requested =
  let table = Lazy.force crossing_callstacks in
  let observed = List.map (fun ((_, p), _, _) -> p) !calls in
  let rebuilt =
    Hashtbl.fold (fun p _ acc -> p :: acc) table []
    |> List.filter
      (fun p ->
         not (List.mem p observed)
         && match p.calls with
         | (name, _) :: _ -> List.mem name requested
         | [] -> false)
    |> List.sort_uniq compare
  in
  let only a b = List.filter (fun x -> not (List.mem x b)) a in
  let print title what stacks =
    if stacks <> [] then begin
      Format.printf "@[<v 2>%s:" title;
      List.iter
        (fun p ->
           let shown = display_portable p in
           Format.printf "@ %s" shown;
           record [ "below rebuilt"; what; shown ])
        stacks;
      Format.printf "@]@."
    end
  in
  print "Calls below a hit rebuilt by the observer, NOT listed by Eva"
    "not listed" (only rebuilt listed);
  print "Calls below a hit listed by Eva, NOT rebuilt by the observer"
    "not rebuilt" (only listed rebuilt);
  print "Calls below a hit that cross a recursion, rebuilt by the observer"
    "crossing"
    (List.filter (is_crossing table) rebuilt)

(* The case of an unavailable answer at [point] that includes the callstacks
   [stacks]. The cases are numbered as in the closed list of #87. The points
   of the body of a call below a hit that crosses a recursion are rebuilt
   from its start, and are unavailable with it where the cache entry of its
   counterpart reaches them: they are told apart, as case 3b. *)
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
      if crossing point stacks then "3: start below a hit, across a recursion"
      else "none"
    | Some name ->
      if results_disabled name then "5: results disabled"
      else if unrolled name then "2: unrolled recursive calls"
      else if interrupted name then "4: interrupted call"
      else if unknown_footprint name then "6: unknown footprint"
      else if crossing point stacks
      then "3b: body below a hit, across a recursion"
      else "none"

(* ----- Comparison of the answers ----------------------------------------- *)

let counts = Hashtbl.create 5
let memexec_counts = Hashtbl.create 5

(* The number of answers on a callstack that neither the reference nor the
   run with memexec lists: the run with memexec is not compared there. *)
let not_compared = ref 0

let count table v =
  let n = Option.value ~default:0 (Hashtbl.find_opt table v) in
  Hashtbl.replace table v (n + 1)

(* [stacks] are the callstacks that [answer] includes in the current
   project. [v_memexec] is the independent verdict, when compared. *)
let compare_answer point ~what ~stacks description ~reference ~memexec
    ~answer ~v_memexec =
  let v = verdict ~matched:!matched_reference ~reference ~answer () in
  count counts v;
  begin match v_memexec with
    | Some v -> count memexec_counts v
    | None -> incr not_compared
  end;
  let origin =
    if v = Unavailable && model reference = None then ", as in the reference"
    else if
      verdict ~matched:!matched_memexec ~reference:memexec ~answer () = Equal
    then ", as with memexec"
    else ""
  in
  if v <> Equal then
    Format.printf "  %s: %s%s@." description (string_of_verdict v) origin;
  let differs = Option.fold ~none:false ~some:(( <> ) Equal) v_memexec in
  if suite && (v <> Equal || differs) then
    let name = match point.kf with
      | Some kf -> Kernel_function.get_name kf
      | None -> ""
    in
    let case =
      if v = Unavailable then closed_list_case point ~stacks else ""
    in
    record [ "answer"; point.kind; name; description; what;
             string_of_verdict v;
             Option.fold ~none:"not compared" ~some:string_of_verdict
               v_memexec;
             String.trim (Str.global_replace (Str.regexp "^, ") "" origin);
             case ]

(* [listed] are the callstacks that reach [point] in the current project. *)
let compare_point point c ~listed =
  let describe what = point.description ^ ", " ^ what in
  compare_answer point ~what:"joined" ~stacks:listed (describe "joined")
    ~reference:c.reference.joined
    ~memexec:c.memexec.joined ~answer:c.current.joined
    ~v_memexec:(Some c.pair.joined_verdict);
  compare_answer point ~what:"filtered" ~stacks:c.current.filtered_stacks
    (describe "filtered")
    ~reference:c.reference.filtered
    ~memexec:c.memexec.filtered ~answer:c.current.filtered
    ~v_memexec:(Some c.pair.filtered_verdict);
  List.iter
    (fun ((_, p as name), answer) ->
       compare_answer point ~what:"callstack" ~stacks:[ p ]
         (describe (display name))
         ~reference:(find name c.reference.by_callstack)
         ~memexec:(find name c.memexec.by_callstack)
         ~answer ~v_memexec:(List.assoc_opt name c.pair.stack_verdicts))
    c.current.by_callstack

(* The statements unreachable for the passes in one run and not in the
   reference, or the converse: the passes ask whether the state before a
   statement is bottom, and an unavailable answer is not. Those unreachable
   with memexec or with -eva-hit-log and reachable in the reference are
   printed; all are recorded in the summary, with the case of the closed
   list of an unavailable answer. [listed] are the callstacks that reach
   each point in the current project. *)
let compare_unreachable compared ~listed =
  let bottom = function
    | Error Results.Bottom | Ok Cvalue.Model.Bottom -> true
    | _ -> false
  in
  let count run answers =
    let n = List.length (List.filter bottom answers) in
    record [ "unreachable statements"; run; string_of_int n ]
  in
  let befores =
    List.combine compared listed
    |> List.filter (fun ((point, _), _) -> String.equal point.kind "before")
  in
  count "reference" (List.map (fun ((_, c), _) -> c.reference.joined) befores);
  List.iter
    (fun (run, title, answer) ->
       count run (List.map (fun ((_, c), _) -> answer c) befores);
       let only =
         List.filter_map
           (fun ((point, c), listed) ->
              let r = bottom c.reference.joined and a = bottom (answer c) in
              if r = a then None
              else begin
                let unavailable = not a && model (answer c) = None in
                let case =
                  if unavailable && String.equal run "recording"
                  then closed_list_case point ~stacks:listed
                  else ""
                in
                record [ "unreachable"; run;
                         (if a then "only in this run"
                          else "only in the reference");
                         point.description; case ];
                if a then Some point.description else None
              end)
           befores
       in
       if only <> [] then begin
         Format.printf "@[<v 2>Statements unreachable for the passes %s, \
                        and reachable without memexec:" title;
         List.iter (Format.printf "@ %s") only;
         Format.printf "@]@."
       end)
    [ "recording", "with -eva-hit-log", (fun c -> c.current.joined);
      "memexec", "with memexec, without recording",
      (fun c -> c.memexec.joined) ]

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
  verdict ~matched:!matched_reference ~reference:c.reference.joined
    ~answer:c.current.joined () = Equal
  && List.length c.reference.by_callstack = List.length c.current.by_callstack
  && List.for_all
    (fun (name, answer) ->
       verdict ~matched:!matched_reference
         ~reference:(find name c.reference.by_callstack) ~answer () = Equal)
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

(* A name of a variable in a message, as a copy \copy<x>[1] of a variable
   of a recursive call. *)
let name_token =
  Str.regexp
    ("\\\\?[A-Za-z_][A-Za-z0-9_]*"
     ^ "\\(<[^<> \n]*>\\[[0-9]+\\]\\(_[0-9]+\\)*\\)?")

(* The text [text] with each name of [names], a list of pairs, replaced by
   the second name of its pair. *)
let rename_names names text =
  let table = Hashtbl.create 7 in
  List.iter (fun (name, name') -> Hashtbl.replace table name name') names;
  Str.global_substitute name_token
    (fun text ->
       let token = Str.matched_string text in
       Option.value ~default:token (Hashtbl.find_opt table token))
    text

(* Whether the text [text] has one of the names [names]. *)
let has_names names text =
  let rec search start =
    match Str.search_forward name_token text start with
    | exception Not_found -> false
    | position ->
      let token = Str.matched_string text in
      List.mem token names
      || search (position + max 1 (String.length token))
  in
  names <> [] && search 0

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
  (* The bases created by an analysis are named in each project with its own
     suffix of a counter. For a second comparison, the names of the created
     bases of the reference are replaced by those of the bases they match in
     the run compared with it, and the spaces and the line breaks that align
     the names are removed. The run with memexec is compared with the
     reference by the match of these two runs. *)
  let normal text = Str.global_replace (Str.regexp "[ \n]+") " " text in
  List.iter
    (fun (run, o, matched) ->
       let unresolved_names = matched.unresolved_names in
       let reference_text = rename_names matched.names reference.output in
       record [ "messages"; run;
                if String.equal o.output reference.output then "equal"
                else if String.equal (normal o.output) (normal reference_text)
                then "equal up to the names of the created bases"
                else if has_names unresolved_names o.output
                     || has_names unresolved_names reference_text
                then "unresolved"
                else "differ" ])
    [ "recording", current, !matched_reference;
      "memexec", memexec, !matched_pair ]

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
         Option.iter Parameters.AllocBuiltin.set
           (List.assoc name alloc_controls);
         Parameters.Eva.on ();
         analysing := Some name;
         let passes = analyse () in
         analysing := None;
         passes)
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
                 [ Equal; Covers; More_precise; Omits; Unavailable;
                   Unresolved ]))
    [ "recording", counts; "memexec", memexec_counts ];
  record [ "not compared"; "memexec"; string_of_int !not_compared ];
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

(* Whether [point] is under the control HIT_LOG_OBSERVER_UNAVAILABLE: a
   point before or after the statement that has the label it names. *)
let controlled (point : point) =
  match unavailable_control, point.stmt with
  | Some label, Some stmt -> List.mem label (labels stmt)
  | _ -> false

(* Under this control, the callstacks listed with -eva-hit-log at each point,
   [stacks], with those of the start of its function at a controlled
   point. *)
let controlled_stacks points stacks =
  let with_stacks = List.combine points stacks in
  let of_start kf =
    List.find_map
      (fun ((point : point), stacks) ->
         if String.equal point.kind "start"
         && Option.equal Kernel_function.equal point.kf kf
         then Some stacks else None)
      with_stacks
  in
  List.map
    (fun (point, stacks) ->
       if controlled point
       then Option.value ~default:stacks (of_start point.kf) else stacks)
    with_stacks

(* Under this control, the answers with -eva-hit-log, [answers], with each
   answer at a controlled point unavailable, on the callstacks [stacks]. *)
let controlled_answers points stacks answers =
  List.map2
    (fun (point, stacks) a ->
       if controlled point then
         { joined = Error Results.Top; filtered = Error Results.Top;
           by_callstack =
             List.map (fun (cs, _) -> cs, Error Results.Top) a.by_callstack;
           filtered_stacks = List.sort compare (List.map snd stacks) }
       else a)
    (List.combine points stacks) answers

(* After an analysis with -eva-hit-log, Results.is_reachable decides whether
   the state before a statement is bottom without rebuilding this state, in
   most cases. Its answer is compared, before each statement of [points], with
   the joined state of [answers], requested in the current project and
   rebuilt by pasting the Inner parts: the statement is reachable if and only
   if this state is not bottom. The comparison is made in the current
   project, after the requests that are counted and reported to
   Eva.Legacy_read_trap, with the trap off. Each statement where the two
   differ is printed, and the summary then records the phase "reachability
   differs", which dev/hit-log-suite.py reports as a failure. When the
   environment variable HIT_LOG_OBSERVER_REACHABILITY names a file, a line
   is appended to it: the working directory of the run, the number of
   statements compared, and the number where the two differ. *)
let reachability_file =
  match Sys.getenv_opt "HIT_LOG_OBSERVER_REACHABILITY" with
  | None | Some "" -> None
  | Some file -> Some file

let check_reachability points answers =
  let bottom = function
    | Error Results.Bottom | Ok Cvalue.Model.Bottom -> true
    | _ -> false
  in
  let compared, differ =
    List.fold_left2
      (fun (compared, differ as acc) point answer ->
         match point.kind, point.stmt with
         | "before", Some stmt ->
           let reachable = Results.is_reachable stmt in
           let differ =
             if reachable = bottom answer.joined
             then (point.description, reachable) :: differ
             else differ
           in
           compared + 1, differ
         | _ -> acc)
      (0, []) points answers
  in
  if differ <> [] then begin
    Format.printf "@[<v 2>Reachability: Results.is_reachable differs from the \
                   joined state before %d of the %d statements:"
      (List.length differ) compared;
    List.iter
      (fun (description, reachable) ->
         Format.printf "@ %s: %s, joined state %s" description
           (if reachable then "reachable" else "unreachable")
           (if reachable then "bottom" else "not bottom"))
      (List.rev differ);
    Format.printf "@]@.";
    record [ "phase"; "reachability differs" ]
  end;
  Option.iter
    (fun file ->
       let flags = [ Open_wronly; Open_append; Open_creat; Open_text ] in
       let channel = open_out_gen flags 0o644 file in
       Printf.fprintf channel "%s\t%d\t%d\n"
         (Sys.getcwd ()) compared (List.length differ);
       close_out channel)
    reachability_file

let observe () =
  let current = Project.current () in
  collect_existing_variables ();
  print_controls ();
  let reference, reference_passes =
    copy_and_analyse "reference" ~memexec:false
  in
  let with_memexec, memexec_passes = copy_and_analyse "memexec" ~memexec:true in
  record [ "phase"; "recording" ];
  Parameters.Eva.on ();
  observing_calls := true;
  analysing := Some "recording";
  let current_passes = analyse () in
  analysing := None;
  observing_calls := false;
  print_calls ();
  print_heap_calls ();
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
    let current_stacks = controlled_stacks (points ()) current_stacks in
    let starts =
      List.combine (points ()) current_stacks
      |> List.filter_map
        (fun (point, stacks) ->
           if String.starts_with ~prefix:"start of " point.trap
           then Some stacks else None)
    in
    let below_stacks = print_below starts in
    let requested =
      List.filter_map
        (fun point ->
           match point.kind, point.kf with
           | ("start" | "start without body"), Some kf ->
             Some (Kernel_function.get_name kf)
           | _ -> None)
        (points ())
    in
    print_rebuilt ~listed:(List.map snd below_stacks) ~requested;
    let below = List.map fst below_stacks in
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
      in_project project
        (fun points ->
           List.map2
             (fun (point, in_reference) stacks ->
                answers point ~in_reference stacks)
             (List.combine points reference_stacks) stacks)
    in
    let own_reference = answers_in reference in
    let own_memexec = answers_in with_memexec in
    let answers, reported_answers =
      with_trap (fun () -> answers_in current)
    in
    check_reachability (points ()) answers;
    let answers = controlled_answers (points ()) current_stacks answers in
    let reported = reported_stacks @ reported_answers in
    (* The reference and the run with memexec are each compared with the run
       with -eva-hit-log, with its created bases; and with each other, with
       those of the run with memexec, on the callstacks that one of the two
       lists. *)
    let blocks project run answers = Project.on project (created run) answers in
    let ref_blocks = blocks reference "reference" own_reference in
    let mem_blocks = blocks with_memexec "memexec" own_memexec in
    let recording_blocks = created "recording" answers in
    let reference_answers, matched =
      rename ~source:ref_blocks ~target:recording_blocks own_reference
    in
    matched_reference := matched;
    let memexec_answers, matched =
      rename ~source:mem_blocks ~target:recording_blocks own_memexec
    in
    matched_memexec := matched;
    let pair_stacks =
      List.map2 (fun r m -> union [ r; m ]) reference_stacks memexec_stacks
    in
    let pair, matched =
      compare_pair with_memexec ~source:ref_blocks ~target:mem_blocks
        own_reference own_memexec pair_stacks
    in
    matched_pair := matched;
    print_matches ();
    let compared =
      List.map2
        (fun (reference, memexec) (current, pair) ->
           { reference; memexec; current; pair })
        (List.combine reference_answers memexec_answers)
        (List.combine answers pair)
    in
    let compared = List.combine (points ()) compared in
    List.iter print_labelled compared;
    print_control compared;
    let initial = snd (List.hd compared) in
    Format.printf "Initial state: %s.@."
      (string_of_verdict
         (verdict ~matched:!matched_reference
            ~reference:initial.reference.joined
            ~answer:initial.current.joined ()));
    Format.printf "Differences with the run without memexec:@.";
    List.iter2
      (fun (point, c) listed ->
         compare_point point c ~listed:(List.map snd listed))
      compared current_stacks;
    compare_unreachable compared
      ~listed:(List.map (List.map snd) current_stacks);
    let get v = Option.value ~default:0 (Hashtbl.find_opt counts v) in
    Format.printf "Answers: %d equal, %d covering, %d more precise, \
                   %d omitting, %d unavailable%s.@."
      (get Equal) (get Covers) (get More_precise) (get Omits) (get Unavailable)
      (if get Unresolved = 0 then ""
       else Format.sprintf ", %d unresolved" (get Unresolved));
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
                 (verdict ~matched:!matched_reference
                    ~reference:initial.reference.joined
                    ~answer:initial.current.joined ()) ];
      record_summary ~below ~different_stacks ~different_filtered ~compared
        ~reported ~memexec_passes ~current_passes;
      record_outputs ~reference ~memexec ~current
    end
  end;
  record [ "phase"; "done" ]

(* The reference is analysed without memexec, which takes hours on a case
   study such as monocypher or gzip, for no gain: their reference is not
   needed. The observer therefore observes the programs of the tests of Eva
   only. HIT_LOG_OBSERVER_ANY_PROGRAM=1 lifts this limit. The statement count
   cannot replace this check: value/unfold.i has more statements than gzip
   or monocypher.

   The sources of the program are read from the project, whichever way its
   AST was built: from the command line, by File.init_from_c_files with no
   file on the command line, or by -load. They are the files of the
   locations of the globals of the AST, which are kept with the AST, by
   -load and in the projects that a visitor derives from it, and which
   include the headers; and the files registered for parsing
   (File.get_all), which name an input file even when it declares no
   global. Kernel.Files alone is empty after File.init_from_c_files. A
   program whose AST has globals but no source is refused.

   Each source, once its symbolic links are resolved, must lie in a
   directory plugins/eva/tests, or be a file of a share directory of
   Frama-C: under that directory once resolved, or the resolved path of
   the file at the same relative path in that directory. The second case is
   the install layout of Dune, where each file of the share directory is a
   symbolic link into the build tree. A file is thus accepted as a share
   file only if one of the share directories leads to it. A source whose
   path cannot be resolved, as a symbolic link that no longer exists, is
   refused.

   The guard prevents an accidental run on a case study; it does not prove
   where every line comes from. It trusts the contents of the share
   directories (a symbolic link placed there is accepted wherever it
   points), and any directory named plugins/eva/tests. A header that
   declares no global, as one that only defines macros or is included in a
   function body, is not seen. In a project derived by a visitor, where
   File.get_all is empty, a #line directive naming a test file hides the
   real file. A file reached through a link to the source directory
   plugins/eva/share is refused; no run that the observer observes needs
   one. *)
type sources = {
  foreign: string list;
  unresolved: string list;
  no_source: bool;
}

let check_sources () =
  let real path =
    try Some (Unix.realpath path) with Unix.Unix_error _ -> None
  in
  let under dir path = String.starts_with ~prefix:(dir ^ "/") path in
  let shares = List.map Filepath.to_string_abs System_config.Share.dirs in
  let real_shares = List.filter_map real shares in
  (* The paths [dir/r] of the share directories, for each relative path [r]
     that ends [path] and is made of whole components. *)
  let share_candidates path =
    let rec suffixes acc = function
      | [] -> acc
      | _ :: rest as components ->
        suffixes (String.concat "/" components :: acc) rest
    in
    let components =
      List.filter (fun c -> c <> "") (String.split_on_char '/' path)
    in
    let relative = suffixes [] components in
    List.concat_map
      (fun dir -> List.map (fun r -> dir ^ "/" ^ r) relative)
      shares
  in
  let in_share path =
    List.exists (fun dir -> under dir path) real_shares
    || List.exists
      (fun candidate -> real candidate = Some path)
      (share_candidates path)
  in
  let in_tests path =
    let marker = "/plugins/eva/tests/" in
    let n = String.length marker and l = String.length path in
    let rec from i =
      i + n <= l && (String.sub path i n = marker || from (i + 1))
    in
    from 0
  in
  let ast = Ast.get () in
  let paths = Hashtbl.create 17 in
  let add path =
    if not (Filepath.is_empty path) then
      Hashtbl.replace paths (Filepath.to_string_abs path) ()
  in
  List.iter
    (fun global ->
       let pos = Fileloc.start_pos (Cil_datatype.Global.loc global) in
       if Filepos.generated_by pos = None then add (Filepos.path pos))
    ast.Cil_types.globals;
  List.iter
    (function
      | File.NeedCPP (path, _, _, _) | File.NoCPP path
      | File.External (path, _) -> add path)
    (File.get_all ());
  let paths =
    List.sort String.compare (Hashtbl.fold (fun p () acc -> p :: acc) paths [])
  in
  let unresolved, resolved =
    List.partition_map
      (fun path ->
         match real path with
         | None -> Either.Left path
         | Some resolved -> Either.Right (path, resolved))
      paths
  in
  { foreign =
      List.filter_map
        (fun (path, resolved) ->
           if in_tests resolved || in_share resolved then None
           else Some path)
        resolved;
    unresolved;
    no_source = paths = [] && ast.Cil_types.globals <> [] }

let refusal sources =
  let list = String.concat ", " in
  List.filter_map Fun.id
    [ (if sources.no_source then
         Some "the AST has globals but no source file"
       else None);
      (if sources.foreign <> [] then
         Some ("these source files are outside plugins/eva/tests and the \
                share directories of Frama-C: " ^ list sources.foreign)
       else None);
      (if sources.unresolved <> [] then
         Some ("these source paths are unresolvable: "
               ^ list sources.unresolved)
       else None) ]

let observe_stage () =
  let refused =
    if Sys.getenv_opt "HIT_LOG_OBSERVER_ANY_PROGRAM" = Some "1" then []
    else refusal (check_sources ())
  in
  if refused <> [] then begin
    record [ "error"; "sources outside the tests of Eva" ];
    Kernel.abort
      "the hit log observer analyses its reference without memexec, and \
       observes the tests of Eva only; %s. Set \
       HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway."
      (String.concat "; " refused)
  end
  else if suite && Analysis.is_computed () then begin
    record [ "error"; "the analysis is computed before the observer starts" ];
    Format.printf "The analysis is computed before the observer starts: no \
                   observation.@."
  end
  else observe ()

let main () =
  incr stage;
  match stages with
  | Some channel -> write_stage channel
  | None ->
    if Option.fold ~none:true ~some:(Int.equal !stage) selected_stage
    then observe_stage ()

(* Equal contents, but a four-byte read is guaranteed only in the target. *)
let make_bound_base label ~weak ~min_alloc =
  let vi = Cil.makeGlobalVar ~source:false label Cil_const.intType in
  let validity =
    Base.Variable (Base.create_variable_validity ~weak
                     ~min_alloc:(Z.of_int min_alloc) ~max_alloc:(Z.of_int 31))
  in
  let base = Base.register_allocated_var vi Base.Malloc validity in
  let size =
    Lattice_bounds.Bottom.non_bottom
      (Cvalue.V_Offsetmap.size_from_validity validity)
  in
  let offsetmap =
    Cvalue.V_Offsetmap.create_isotropic ~size Cvalue.V_Or_Uninitialized.bottom
    |> Cvalue.V_Offsetmap.add ~exact:true (Z.zero, Z.of_int 31)
      (Cvalue.V_Or_Uninitialized.uninitialized, Z.one, Abstract_interp.Rel.zero)
  in
  base, Cvalue.Model.add_base base offsetmap Cvalue.Model.empty_map

let point_of_model model =
  { joined = Ok model; filtered = Ok model;
    by_callstack = []; filtered_stacks = [] }

let check_bounds ref_min answer_weak expected =
  Hashtbl.clear allocations;
  let ref_base, ref_model =
    make_bound_base "bound_reference" ~weak:false ~min_alloc:ref_min
  and answer_base, answer_model =
    make_bound_base "bound_answer" ~weak:answer_weak ~min_alloc:31
  in
  let site = { thread = 0; entry = "synthetic"; calls = [] } in
  List.iter
    (fun (run, base) ->
       let a = allocations_of run in
       Base.Hashtbl.replace a.origins base (site, 0);
       Hashtbl.replace a.by_site site 1)
    [ "reference", ref_base; "recording", answer_base ];
  let reference = point_of_model ref_model
  and answer = point_of_model answer_model in
  let renamed, matched =
    rename ~source:(created "reference" [reference])
      ~target:(created "recording" [answer]) [reference]
  in
  assert (verdict ~matched ~reference:(List.hd renamed).joined
            ~answer:answer.joined () = expected)

module Bound_state =
  State_builder.Option_ref (Datatype.Pair (Base) (Cvalue.Model)) (struct
    let name = "Hit_log_observer.Bound_state"
    let dependencies = [Ast.self]
  end)

let check_prefix ~copied ~weak ~min_alloc =
  Hashtbl.clear allocations;
  let label = "prefix_block" in
  let base, model = make_bound_base label ~weak:false ~min_alloc:31 in
  Bound_state.set (base, model);
  let project = Project.create_by_copy ~last:false "prefix_reference" in
  let reference, source =
    Project.on project
      (fun () ->
         let other, model =
           if copied then Bound_state.get ()
           else make_bound_base label ~weak:false ~min_alloc:31
         in
         assert (other != base && Base.equal other base = copied);
         begin match Base.validity other with
           | Base.Variable v ->
             Base.update_variable_validity v ~weak ~min_alloc:(Z.of_int min_alloc)
               ~max_alloc:(Z.of_int 31)
           | _ -> assert false
         end;
         let answers = [point_of_model model] in
         answers, created "reference" answers)
      ()
  in
  let answer = point_of_model model in
  let renamed, matched =
    rename ~source ~target:(created "recording" [answer]) reference
  in
  assert (verdict ~matched ~reference:(List.hd renamed).joined
            ~answer:answer.joined () = Unresolved)

(* A pointer split across two intervals of a weak block must keep its
   fragments when compared with memexec, even when recording has a strong
   copy of the same block. *)
module Pointer_state =
  State_builder.Option_ref (Datatype.Pair (Base) (Base)) (struct
    let name = "Hit_log_observer.Pointer_state"
    let dependencies = [Ast.self]
  end)

let check_pointer_fragments () =
  Hashtbl.clear allocations;
  let last = Z.of_int 31 and width = Z.of_int 32 in
  let block, _ = make_bound_base "pointer_block" ~weak:false ~min_alloc:31 in
  let slot =
    Cil.makeGlobalVar ~source:false "pointer_slot" Cil_const.voidPtrType
    |> fun vi -> Base.register_memory_var vi (Base.Known (Z.zero, last))
  in
  let weaken block =
    match Base.validity block with
    | Base.Variable v ->
      Base.update_variable_validity v ~weak:true ~min_alloc:last ~max_alloc:last
    | _ -> assert false
  in
  let pointer block =
    Cvalue.V_Or_Uninitialized.initialized (Cvalue.V.inject block Ival.zero)
  in
  let pointers = pointer block in
  Pointer_state.set (block, slot);
  let copy name ~split =
    let project = Project.create_by_copy ~last:false name in
    let answer, blocks =
      Project.on project
        (fun () ->
           let other, slot = Pointer_state.get () in
           assert (Base.equal block other && block != other);
           weaken other;
           let value = pointer other in
           let offsetmap =
             if split then
               let add lo hi map =
                 Cvalue.V_Offsetmap.add ~exact:true (lo, hi)
                   (value, width, Abstract_interp.Rel.sub_abs lo Z.zero) map
               in
               Cvalue.V_Offsetmap.empty
               |> add Z.zero (Z.of_int 15) |> add (Z.of_int 16) last
             else Cvalue.V_Offsetmap.create ~size:width value ~size_v:width
           in
           let answer = point_of_model
               (Cvalue.Model.add_base slot offsetmap Cvalue.Model.empty_map)
           in
           answer, created name [answer])
        ()
    in
    project, answer, blocks
  in
  let _, reference, source = copy "reference" ~split:true in
  let project, answer, target = copy "memexec" ~split:false in
  let check () =
    let compared, _ =
      compare_pair project ~source ~target [reference] [answer] [[]]
    in
    assert ((List.hd compared).joined_verdict = Omits)
  in
  assert (Cvalue.V_Or_Uninitialized.cardinal_zero_or_one pointers);
  check ();
  weaken block;
  assert (not (Cvalue.V_Or_Uninitialized.cardinal_zero_or_one pointers));
  check ()

let () =
  Boot.Main.extend
    (if Sys.getenv_opt "HIT_LOG_OBSERVER_CHECK_BOUNDS" = Some "1" then
       fun () ->
         File.init_cil ();
         check_bounds 31 false Equal;
         check_bounds 31 true Covers;
         check_bounds 7 false Unresolved;
         check_bounds 7 true Unresolved;
         check_prefix ~copied:true ~weak:false ~min_alloc:7;
         check_prefix ~copied:true ~weak:true ~min_alloc:31;
         check_prefix ~copied:false ~weak:false ~min_alloc:7;
         check_pointer_fragments ()
     else main)
