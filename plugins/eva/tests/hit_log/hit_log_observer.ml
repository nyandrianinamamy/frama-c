(* Observer of the tests of option -eva-hit-log.

   The current project is analysed with the options of the test, which set
   -eva-hit-log. Two copies of it, made before, are analysed without
   recording: the reference, without memexec, and a run with memexec. After
   the analyses, the observer asks Eva.Results, in each project, for the state
   at the start of each function and before and after each statement, joined
   over the callstacks, for each callstack that reaches the point, and through
   a filter on the callstacks.

   It prints:
   - the calls of the analysis with -eva-hit-log, with the cache entry they
     compute or use;
   - the states at the labelled statements, and those of the reference when
     they differ;
   - for each hit on another callstack than the analysed call of its cache
     entry, the variables whose values differ between the two callstacks, at
     the points of the function;
   - the verdict on the initial state, then each answer that is not equal to
     the reference, with one of these verdicts:
     "covers": the answer includes the reference and is larger;
     "more precise": the answer is included in the reference and smaller;
     "OMITS": the answer does not include the reference;
     "unavailable": the answer is top, as for a function without results.
     A verdict is followed by "as with memexec" when the answer equals that of
     the run with memexec and without recording: the difference comes from
     the analysis with memexec, not from the answers served from the hit log.
     "unavailable" is followed by "as in the reference" when the reference is
     top as well;
   - the report of Eva.Legacy_read_trap for the requests made in the current
     project. *)

open Eva

(* ----- Calls of the analysis --------------------------------------------- *)

type call_kind = Analysed of int | Hit of int | Other of string

let string_of_callstack = Format.asprintf "%a" Legacy_read_trap.pretty_callstack

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
         calls := (string_of_callstack callstack, kf, kind) :: !calls)

let print_calls () =
  Format.printf "@[<v 2>Calls:";
  List.iter
    (fun (callstack, _kf, kind) ->
       match kind with
       | Analysed id ->
         Format.printf "@ %s: analysed, cache entry %d" callstack id
       | Hit id -> Format.printf "@ %s: hit of cache entry %d" callstack id
       | Other s -> Format.printf "@ %s: %s" callstack s)
    (List.rev !calls);
  Format.printf "@]@."

(* ----- Requests ---------------------------------------------------------- *)

type answer = Cvalue.Model.t Results.result

(* The requests made in the current project, counted to check the report of
   Eva.Legacy_read_trap. *)
let count = ref 0
let request f x = incr count; f x

let state request_ : answer =
  request Results.get_cvalue_model_result request_

(* The callstacks of the two projects are paired by their printed form:
   two calls of a function on one line would be confused. *)
let callstacks request_ =
  let list =
    request Results.callstacks request_
    |> List.map (fun cs -> string_of_callstack cs, cs)
    |> List.sort (fun (s, _) (s', _) -> String.compare s s')
  in
  let names = List.map fst list in
  if List.length (List.sort_uniq String.compare names) <> List.length names
  then Format.printf "Two callstacks are printed alike: %s.@."
      (String.concat ", " names);
  list

(* The answers at one point. *)
type point_answers = {
  joined: answer;
  filtered: answer;
  by_callstack: (string * answer) list;
}

let answers request_ =
  let joined = state request_ in
  let filtered = state Results.(request_ |> filter_callstack (fun _ -> true)) in
  let by_callstack =
    List.map
      (fun (name, cs) -> name, state Results.(request_ |> in_callstack cs))
      (callstacks request_)
  in
  { joined; filtered; by_callstack }

type point = {
  description: string;
  request: Results.request;
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
        request = Results.at_start_of kf; kf = Some kf; show = labelled }
    in
    let of_stmt stmt =
      [ { description = describe_stmt "before" stmt;
          request = Results.before stmt; kf = Some kf;
          show = labelled && labels stmt <> [] };
        { description = describe_stmt "after" stmt;
          request = Results.after stmt; kf = Some kf;
          show = labelled && Cil_datatype.Stmt.equal stmt return } ]
    in
    start :: List.concat_map of_stmt stmts
  in
  { description = "initial state"; request = Results.at_start; kf = None;
    show = false }
  :: { description = "final state"; request = Results.at_end (); kf = None;
       show = false }
  :: List.concat_map of_function functions

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

let missing = Error Results.Bottom
let find name list = Option.value ~default:missing (List.assoc_opt name list)

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

(* A callstack missing from the answers of a point is unreachable, unless
   the joined answer is unavailable: the callstacks of a function without
   results are unknown. *)
let compare_point point c =
  let describe what = point.description ^ ", " ^ what in
  let default = if model c.current.joined = None then Error Results.Top
    else missing
  in
  let find_current name =
    Option.value ~default (List.assoc_opt name c.current.by_callstack)
  in
  compare_answer (describe "joined") ~reference:c.reference.joined
    ~memexec:c.memexec.joined ~answer:c.current.joined;
  compare_answer (describe "filtered") ~reference:c.reference.filtered
    ~memexec:c.memexec.filtered ~answer:c.current.filtered;
  let names =
    List.map fst c.reference.by_callstack @ List.map fst c.current.by_callstack
    |> List.sort_uniq String.compare
  in
  List.iter
    (fun name ->
       compare_answer (describe name)
         ~reference:(find name c.reference.by_callstack)
         ~memexec:(find name c.memexec.by_callstack)
         ~answer:(find_current name))
    names

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
   callstacks, at the points of the function. *)
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
          let points = ref 0 and variables = ref [] in
          List.iter
            (fun (point, c) ->
               if Option.equal Kernel_function.equal point.kf (Some kf)
               then begin
                 incr points;
                 let a = find entry c.current.by_callstack in
                 let b = find hit c.current.by_callstack in
                 variables := differing_variables a b @ !variables
               end)
            compared;
          let variables = List.sort_uniq String.compare !variables in
          Format.printf "  %s, hit of cache entry %d, against %s: %s, at %d \
                         points.@."
            hit id entry
            (if variables = [] then "no difference"
             else "differs on " ^ String.concat ", " variables)
            !points
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
let answers_in project =
  Project.on project
    (fun () -> List.map (fun p -> answers p.request) (points ())) ()

let main () =
  let current = Project.current () in
  let reference = copy_and_analyse "reference" ~memexec:false in
  let with_memexec = copy_and_analyse "memexec" ~memexec:true in
  observing_calls := true;
  analyse ();
  observing_calls := false;
  print_calls ();
  let reference_answers = answers_in reference in
  let memexec_answers = answers_in with_memexec in
  let points = points () in
  assert (Project.equal current (Project.current ()));
  Legacy_read_trap.start ();
  count := 0;
  let answers = List.map (fun p -> answers p.request) points in
  Legacy_read_trap.stop ();
  let reported = Legacy_read_trap.requests () in
  let reference_answers = rename ~into:answers reference_answers in
  let memexec_answers = rename ~into:answers memexec_answers in
  let compared =
    List.map2
      (fun (reference, memexec) current -> { reference; memexec; current })
      (List.combine reference_answers memexec_answers) answers
  in
  let compared = List.combine points compared in
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
  Format.printf "Answers: %d equal, %d covering, %d more precise, %d omitting, \
                 %d unavailable.@."
    (get Equal) (get Covers) (get More_precise) (get Omits) (get Unavailable);
  let reads = List.concat_map (fun r -> r.Legacy_read_trap.reads) reported in
  Format.printf "Requests made: %d; reported by the trap: %d; reads of the \
                 legacy store: %d.@."
    !count (List.length reported) (List.length reads);
  List.iter
    (fun r -> if r.Legacy_read_trap.reads <> [] then
        Format.printf "%a@." Legacy_read_trap.pretty_request r)
    reported

let () = Boot.Main.extend main
