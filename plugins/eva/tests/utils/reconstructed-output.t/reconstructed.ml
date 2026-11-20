(* Final values, the logic label Init and snapshots of the results of Eva,
   read from the hit log (prototype). See run.t.

   The script supplies the initial memory and the argument of main, and runs
   two analyses of inputs.i, saving the results of each. It then clears the
   results and restores each snapshot in turn. After each analysis and each
   restoration, it replays the same requests and writes their answers to the
   file named by the step, such as [fresh-1] or [restored-1], in the
   directory given by the environment variable ANSWERS.

   The guard records every legacy read and every answer of the hit log. The
   environment variable FORBID lists the migrated readers whose legacy reads
   abort the run: [display] (final values), [init] (label Init), [export]
   (states of a snapshot) and [replay] (requests on restored results). *)

open Cil_types

module Guard = Eva.Legacy_read_guard
module R = Eva.Results

let log fmt = Format.printf ("[reconstructed] " ^^ fmt ^^ "@.")

(* ----- Guard -------------------------------------------------------------- *)

let labels = [
  "display", "Eva.Cvalue_domain.display_final_state";
  "init", "Eva.Eval_terms.add_init";
  "export", "Eva.Eva_results.export_states";
]

let forbidden =
  match Sys.getenv_opt "FORBID" with
  | None | Some "" -> []
  | Some names -> String.split_on_char ',' names

(* Arms the guard. While requests replay on restored results, a forbidden
   replay traps every read of the request phase. *)
let arm ~replay =
  let trap = replay && List.mem "replay" forbidden in
  Guard.arm (if trap then Guard.Trap [ Guard.Request ] else Guard.Record);
  Guard.forbid (List.filter_map (fun n -> List.assoc_opt n labels) forbidden)

(* Whether some reads were logged. The exact counts depend on the readers
   that other changes migrate, such as the nested requests of InOut. *)
let some_reads = function
  | [] -> "no legacy read"
  | _ :: _ -> "legacy reads"

let read_by label (r : Guard.read) = List.mem label r.readers

(* ----- Program ------------------------------------------------------------ *)

let global name =
  let find vi _ acc = if vi.vname = name then Some vi else acc in
  Option.get (Globals.Vars.fold find None)

let labelled name =
  let has_label = function Label (l, _, _) -> l = name | _ -> false in
  let find kf acc =
    match acc with
    | None when Kernel_function.is_definition kf ->
      let body = Kernel_function.get_definition kf in
      List.find_opt (fun s -> List.exists has_label s.labels) body.sallstmts
    | _ -> acc
  in
  Option.get (Globals.Functions.fold find None)

let int n = Cvalue.V.inject_int (Z.of_int n)

(* Every global is initialized to 0, except g. *)
let initial_memory ~g =
  let bind vi _ state =
    if not vi.vsource then state
    else
      let base = Base.of_varinfo vi in
      match Cvalue.Default_offsetmap.default_offsetmap base with
      | `Bottom -> state
      | `Value offsetmap ->
        let state = Cvalue.Model.add_base base offsetmap state in
        let value = if vi.vname = "g" then int g else int 0 in
        Cvalue.Model.add_binding ~exact:true state
          (Locations.of_varinfo vi) value
  in
  Globals.Vars.fold bind Cvalue.Model.empty_map

(* ----- Requests ----------------------------------------------------------- *)

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

let pretty_result pretty fmt = function
  | Ok v -> pretty fmt v
  | Error R.Bottom -> Format.pp_print_string fmt "error bottom"
  | Error R.Top -> Format.pp_print_string fmt "error top"
  | Error R.DisabledDomain -> Format.pp_print_string fmt "error disabled"

let pretty_status = function
  | Eva.Analysis.Unreachable -> "unreachable"
  | SpecUsed -> "specification used"
  | Builtin name -> "builtin " ^ name
  | Analyzed Complete -> "analyzed complete"
  | Analyzed Partial -> "analyzed partial"
  | Analyzed NoResults -> "analyzed without results"

(* The requests on the statement P of f, on each of its callstacks, on a
   selection and on none; the initial state and the start of main; the
   reachability of P and of the dead statement D. *)
let replay fmt =
  let p = labelled "P" and d = labelled "D" and g = global "g" in
  let f = Kernel_function.find_englobing_kf p in
  let main = fst (Globals.entry_point ()) in
  let answer name pp x = Format.fprintf fmt "@[<v 2>%s:@ %a@]@." name pp x in
  let model = pretty_result Cvalue.Model.pretty in
  let value = pretty_result Cvalue.V.pretty in
  let names = function
    | [] -> "none"
    | stacks -> String.concat " " (List.map stack_name stacks)
  in
  answer "callstacks before P" Format.pp_print_string
    (names R.(before p |> callstacks));
  (* The callstacks of f, also known when its states are not recorded. *)
  let stacks = R.(at_start_of f |> callstacks) in
  answer "callstacks at the start of f" Format.pp_print_string (names stacks);
  answer "before P" model R.(before p |> get_cvalue_model_result);
  answer "after P" model R.(after p |> get_cvalue_model_result);
  List.iter (fun stack ->
      let on point = R.(point |> in_callstack stack) in
      let name = stack_name stack in
      answer ("before P on " ^ name) model
        R.(on (before p) |> get_cvalue_model_result);
      answer ("after P on " ^ name) model
        R.(on (after p) |> get_cvalue_model_result))
    stacks;
  answer "g before P on the selected callstacks" value
    R.(before p |> in_callstacks stacks |> eval_var g |> as_cvalue_result);
  let last = List.rev stacks |> List.hd in
  answer "g before P on the callstack that the predicate keeps" value
    R.(before p |> filter_callstack (Eva.Callstack.equal last)
       |> eval_var g |> as_cvalue_result);
  answer "g before P on no callstack" value
    R.(before p |> in_callstacks [] |> eval_var g |> as_cvalue_result);
  answer "initial state" model R.(at_start |> get_cvalue_model_result);
  answer "start of main" model R.(at_start_of main |> get_cvalue_model_result);
  answer "P reachable" Format.pp_print_bool (R.is_reachable p);
  answer "before P empty" Format.pp_print_bool R.(before p |> is_empty);
  answer "D reachable" Format.pp_print_bool (R.is_reachable d);
  answer "before D empty" Format.pp_print_bool R.(before d |> is_empty);
  answer "before D" model R.(before d |> get_cvalue_model_result)

(* The status table of f, which Eva.Results.are_available and
   Eva.Analysis.status read. *)
let metadata fmt =
  let f = Kernel_function.find_englobing_kf (labelled "P") in
  Format.fprintf fmt "f available: %b@." (R.are_available f);
  Format.fprintf fmt "f status: %s@." (pretty_status (Eva.Analysis.status f))

(* The directory of the answers, from the environment variable ANSWERS. *)
let directory = Option.value ~default:"." (Sys.getenv_opt "ANSWERS")

let write_answers ~replay:trap name =
  let channel = open_out (Filename.concat directory name) in
  let fmt = Format.formatter_of_out_channel channel in
  arm ~replay:trap;
  let (), reads = Guard.observe (fun () -> replay fmt) in
  arm ~replay:false;
  metadata fmt;
  Format.pp_print_flush fmt ();
  close_out channel;
  log "%s: replayed with %s" name (some_reads reads)

(* The status that Eva emits for each check, which reads the label Init. *)
let statuses () =
  let pretty fmt = function
    | Property_status.Never_tried -> Format.pp_print_string fmt "never tried"
    | Best (status, _) -> Property_status.Emitted_status.pretty fmt status
    | Inconsistent _ -> Format.pp_print_string fmt "inconsistent"
  in
  Annotations.iter_all_code_annot (fun stmt _emitter ca ->
      match ca.annot_content with
      | AAssert (_, { tp_statement = { pred_name = name :: _; _ }; _ }) ->
        let kf = Kernel_function.find_englobing_kf stmt in
        let ip = Property.ip_of_code_annot_single kf stmt ca in
        log "status %s: %a" name pretty (Property_status.get ip)
      | _ -> ())

(* ----- Steps -------------------------------------------------------------- *)

let analyze ~step ~g ~n =
  Eva.Eva_results.set_initial_state (initial_memory ~g);
  Eva.Eva_results.set_main_args [ int n ];
  (* The final values are printed only when Eva is enabled. *)
  Eva.Parameters.Eva.set true;
  log "analysis %s: g = %d in the supplied memory, n = %d" step g n;
  Eva.Analysis.compute ();
  statuses ();
  write_answers ~replay:false ("fresh-" ^ step);
  let results, reads = Guard.observe Eva.Eva_results.get_results in
  let states = List.filter (read_by (List.assoc "export" labels)) reads in
  log "snapshot %s: states exported with %s" step (some_reads states);
  results

let restore ~step results =
  let (), reads =
    Guard.observe (fun () -> Eva.Eva_results.set_results results)
  in
  log "snapshot %s: restored with %s" step (some_reads reads);
  statuses ();
  write_answers ~replay:true ("restored-" ^ step)

(* The reads of the run made on behalf of a migrated reader or of the
   snapshot functions of Eva_results, grouped by phase, enclosing readers,
   access and store, in order of first occurrence; then, for each migrated
   reader, whether it read the legacy store and whether the hit log served
   it. The other reads belong to readers that this test does not cover. *)
let summary () =
  let reads = Guard.reads () in
  let snapshot label = String.starts_with ~prefix:"Eva.Eva_results." label in
  let covered (r : Guard.read) =
    List.exists snapshot r.readers
    || List.exists (fun (_, label) -> read_by label r) labels
  in
  let key (r : Guard.read) =
    Guard.phase_name r.phase, String.concat ">" r.readers,
    Guard.access_name r.access, r.store
  in
  let order =
    List.fold_left (fun order r ->
        let k = key r in
        if not (covered r) || List.mem k order then order else k :: order)
      [] reads
  in
  List.iter (fun (phase, readers, access, store) ->
      log "read phase=%s readers=%s access=%s store=%s"
        phase readers access store)
    (List.rev order);
  let resolutions = Guard.resolutions () in
  List.iter (fun (name, label) ->
      let reads = List.filter (read_by label) reads
      and served =
        List.filter (fun r -> List.mem label r.Guard.resolved_readers)
          resolutions
      in
      log "%s: %s, %s" name (some_reads reads)
        (if served = [] then "no answer of the hit log"
         else "answers of the hit log"))
    labels

let main () =
  arm ~replay:false;
  let first = analyze ~step:"1" ~g:7 ~n:10 in
  let second = analyze ~step:"2" ~g:3 ~n:20 in
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ();
  restore ~step:"1" first;
  restore ~step:"2" second;
  summary ()

let () = Boot.Main.extend main
