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
     the legacy store that it reports.
     When the analysis with -eva-hit-log has no result, as when it is refused,
     no request is made. *)

open Eva

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
   call statements when another callstack is printed alike. *)
let display (printed, p) =
  match Hashtbl.find_opt seen printed with
  | Some (_ :: _ :: _) ->
    let sids = List.map (fun (_, sid) -> string_of_int sid) p.calls in
    Format.sprintf "%s (call statements %s)" printed (String.concat ", " sids)
  | _ -> printed

let observing_calls = ref false
let calls = ref []

let () =
  Cvalue_callbacks.register_call_results_hook
    (fun callstack kf _state results ->
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
   call of the analysis. [starts] gives the callstacks of each start. *)
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
  end

(* ----- Points ------------------------------------------------------------ *)

type point = {
  description: string;
  request: Results.request;
  trap: string; (* The point, as Eva.Legacy_read_trap describes it. *)
  kf: Kernel_function.t option; (* The function of the point. *)
  show: bool; (* Whether its states are printed. *)
}

(* A statement, shortened to one line. *)
let pretty_stmt fmt stmt =
  match stmt.Cil_types.skind with
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
        kf = Some kf; show = labelled }
    in
    let of_stmt stmt =
      [ { description = describe_stmt "before" stmt;
          request = Results.before stmt; trap = trap_stmt "before" stmt;
          kf = Some kf; show = labelled && labels stmt <> [] };
        { description = describe_stmt "after" stmt;
          request = Results.after stmt; trap = trap_stmt "after" stmt;
          kf = Some kf;
          show = labelled && Cil_datatype.Stmt.equal stmt return } ]
    in
    start :: List.concat_map of_stmt stmts
  in
  let main = fst (Globals.entry_point ()) in
  { description = "initial state"; request = Results.at_start;
    trap = "initial state"; kf = None; show = false }
  :: { description = "final state"; request = Results.at_end ();
       trap = trap_stmt "after" (Kernel_function.find_return main);
       kf = None; show = false }
  :: List.concat_map of_function functions

(* ----- Requests ---------------------------------------------------------- *)

type answer = Cvalue.Model.t Results.result

(* In the current project, each request is checked against the report of
   Eva.Legacy_read_trap: it must add one request to the report, with the
   description expected. *)
let checking = ref false
let made = ref 0
let unmatched = ref [] (* Expected description and descriptions added. *)

let request ~expected f =
  if not !checking then f ()
  else begin
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
  request ~expected:(point.trap ^ "; every callstack")
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
  by_callstack: (string * answer) list;
}

(* The number of points of the current project at which the filter rejects
   a callstack. *)
let rejecting = ref 0

(* The answers at [point], for the callstacks [stacks]. With several
   callstacks, the filter rejects the first one. *)
let answers (point : point) stacks =
  let state ~expected request_ =
    request ~expected (fun () -> Results.get_cvalue_model_result request_)
  in
  let joined = state ~expected:(point.trap ^ "; joined") point.request in
  let keep =
    match stacks with
    | (_, rejected) :: _ :: _ ->
      if !checking then incr rejecting;
      fun cs -> portable cs <> rejected
    | _ -> fun _ -> true
  in
  let filtered =
    state ~expected:(point.trap ^ "; every callstack, filtered")
      Results.(point.request |> filter_callstack keep)
  in
  let by_callstack =
    List.map
      (fun (printed, cs as stack) ->
         let expected = point.trap ^ "; callstack " ^ printed in
         display stack,
         state ~expected Results.(point.request |> in_callstack (rebuild cs)))
      stacks
  in
  { joined; filtered; by_callstack }


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

let counts = Hashtbl.create 5
let compare_answer description ~reference ~memexec ~answer =
  let v = verdict ~reference ~answer in
  let n = Option.value ~default:0 (Hashtbl.find_opt counts v) in
  Hashtbl.replace counts v (n + 1);
  if v <> Equal then
    let origin =
      if v = Unavailable && model reference = None then ", as in the reference"
      else if verdict ~reference:memexec ~answer = Equal
      then ", as with memexec"
      else ""
    in
    Format.printf "  %s: %s%s@." description (string_of_verdict v) origin

let compare_point point c =
  let describe what = point.description ^ ", " ^ what in
  compare_answer (describe "joined") ~reference:c.reference.joined
    ~memexec:c.memexec.joined ~answer:c.current.joined;
  compare_answer (describe "filtered") ~reference:c.reference.filtered
    ~memexec:c.memexec.filtered ~answer:c.current.filtered;
  List.iter
    (fun (name, answer) ->
       compare_answer (describe name)
         ~reference:(find name c.reference.by_callstack)
         ~memexec:(find name c.memexec.by_callstack)
         ~answer)
    c.current.by_callstack

(* ----- Allocated blocks -------------------------------------------------- *)

(* The bases of allocated blocks are named with a counter shared by the
   projects, and each analysis creates its own: the same block has another
   name in each project. The bases are matched across projects by their name
   without the suffix of the counter, and by their rank of creation. *)

let allocated_bases answers =
  let add acc = function
    | Ok (Cvalue.Model.Map map) ->
      Cvalue.Model.fold
        (fun base _ acc ->
           match base with
           | Base.Allocated _ -> Base.Hptset.add base acc
           | _ -> acc)
        map acc
    | _ -> acc
  in
  List.fold_left
    (fun acc a ->
       List.fold_left add acc
         (a.joined :: a.filtered :: List.map snd a.by_callstack))
    Base.Hptset.empty answers

let counter_suffix = Str.regexp "_[0-9]+$"

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
           List.map (fun (cs, a) -> cs, rename_answer a) a.by_callstack })
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
       Format.printf "@ %s: @[%a@]" name pretty_state answer)
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
                 let a = find (display entry) c.current.by_callstack in
                 let b = find (display hit) c.current.by_callstack in
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

(* ----- Main -------------------------------------------------------------- *)

let analyse () =
  try Analysis.compute ()
  with Log.AbortError _ -> Format.printf "The analysis has stopped.@."

(* Analyses a copy of the current project, made before its analysis. *)
let copy_and_analyse name ~memexec =
  let project = Project.create_by_copy ~last:false name in
  Project.on project
    (fun () ->
       Parameters.Memexec.set memexec;
       Parameters.HitLog.off ();
       analyse ())
    ();
  project

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

let main () =
  let current = Project.current () in
  let reference = copy_and_analyse "reference" ~memexec:false in
  let with_memexec = copy_and_analyse "memexec" ~memexec:true in
  observing_calls := true;
  analyse ();
  observing_calls := false;
  print_calls ();
  if not (Analysis.is_computed ()) then
    Format.printf "The analysis with -eva-hit-log has no result: no request \
                   is made.@."
  else begin
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
    print_below starts;
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
    List.iter (fun (point, c) -> compare_point point c) compared;
    let get v = Option.value ~default:0 (Hashtbl.find_opt counts v) in
    Format.printf "Answers: %d equal, %d covering, %d more precise, \
                   %d omitting, %d unavailable.@."
      (get Equal) (get Covers) (get More_precise) (get Omits) (get Unavailable);
    let reads = List.concat_map (fun r -> r.Legacy_read_trap.reads) reported in
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
      reported
  end

let () = Boot.Main.extend main
