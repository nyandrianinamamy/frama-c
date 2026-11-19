(* Parts of cache entries owned by From and Inout. A first analysis, with
   caching disabled, produces the entries of the callees of parts.c. They are
   supplied to a second analysis, in which the calls to these callees hit
   the entries. EVA_TEST_CACHE_PARTS selects what the two analyses
   compare. *)

open Cil_types

module Producer = Eva.Cache_producer
module Supplied = Eva.Supplied_entries
module Results = Eva.Results

let kf = Globals.Functions.find_by_name
let global name = Globals.Vars.find_from_astinfo name Global
let callees = [ "copy"; "narrow"; "narrow_and_write"; "checked" ]

let line stmt = Fileloc.line (Cil_datatype.Stmt.loc stmt)

(* The calls of [callee], in the order of the program. *)
let calls callee =
  Kernel_function.find_syntactic_callsites (kf callee)
  |> List.map snd |> List.sort Cil_datatype.Stmt.compare

let one_line pp x =
  let buffer = Buffer.create 80 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 1000;
  Format.fprintf fmt "%a@?" pp x;
  let join acc line =
    if acc = "" then line
    else if String.ends_with ~suffix:";" acc then acc ^ " " ^ line
    else acc ^ "; " ^ line
  in
  String.split_on_char '\n' (Buffer.contents buffer)
  |> List.map String.trim |> List.filter (( <> ) "")
  |> List.fold_left join ""

let clear () =
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ()

let stat stat callee = Eva.Statistics.get stat (kf callee)
let hits callee = stat Eva.Statistics.cache_hits callee
let rejected reason callee = stat (Eva.Statistics.cache_rejected reason) callee

(* The first analysis, with caching disabled. Returns the entries produced
   for the callees, oldest first for each callee. *)
let first_analysis () =
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  List.concat_map (fun f -> Producer.entries (kf f)) callees

(* The second analysis, with the entries of the first one supplied. *)
let second_analysis produced =
  List.iter (fun p -> ignore (Supplied.supply_produced p)) produced;
  clear ();
  Eva.Parameters.Memexec.on ();
  Eva.Analysis.compute ()

let part_names produced =
  Eva.Cache_part.names (Eva.Cache_entry.Cvalue.parts
                          (Producer.cache_entry produced))

let print_parts produced =
  List.iter
    (fun p ->
       let entry = Producer.cache_entry p in
       let Eva.Cache_entry.Body f = Eva.Cache_entry.Cvalue.statement entry in
       Format.printf "entry of %a: parts [%s]@." Kernel_function.pretty f
         (String.concat ", " (part_names p)))
    produced

(* ----- From --------------------------------------------------------------- *)

(* The whole table of callwise dependencies, by call site. *)
let callwise_froms () =
  let table = ref [] in
  From.Callwise.iter (fun ki deps -> table := (ki, deps) :: !table);
  List.sort (fun (k, _) (k', _) -> Cil_datatype.Kinstr.compare k k') !table

let same_froms fresh reused =
  List.length fresh = List.length reused
  && List.for_all2
    (fun (k, d) (k', d') ->
       Cil_datatype.Kinstr.equal k k' && Eva.Assigns.equal d d')
    fresh reused

let print_froms table callee =
  List.iter
    (fun stmt ->
       let deps = List.assoc (Kstmt stmt) table in
       Format.printf "%s at line %d: %s@." callee (line stmt)
         (one_line Eva.Assigns.pretty deps))
    (calls callee)

(* -calldeps is set: the dependencies of each call site after the second
   analysis, where the three calls to copy hit, are those of the first. *)
let from () =
  let produced = first_analysis () in
  print_parts produced;
  let fresh = callwise_froms () in
  second_analysis produced;
  Format.printf "hits: copy %d@." (hits "copy");
  let reused = callwise_froms () in
  Format.printf "callwise dependencies equal at %d call sites: %b@."
    (List.length fresh) (same_froms fresh reused);
  print_froms reused "copy";
  print_froms reused "deps_main"

(* -calldeps is set only after the first analysis: its entries have no From
   part. In the second analysis, every candidate is rejected and the bodies
   are analysed, which records their dependencies. *)
let missing () =
  let produced = first_analysis () in
  print_parts produced;
  Dynamic.Parameter.Bool.on "-calldeps" ();
  second_analysis produced;
  List.iter
    (fun f ->
       Format.printf "%s: hits %d, rejected for missing-part %d@." f (hits f)
         (rejected "missing-part" f))
    callees;
  print_froms (callwise_froms ()) "copy"

(* Each entry of copy is supplied again by hand, from the one that the first
   analysis produced, without its Reach part and without the parts of other
   modules. Inout is loaded and its part is needed: each candidate whose key
   matches lacks both parts. The lookup tests the parts of other modules
   first (missing-part), then the Reach part (missing-points). *)
let both () =
  let produced = first_analysis () in
  let by_hand p =
    let module Entry = Eva.Cache_entry.Cvalue in
    let entry = Producer.cache_entry p in
    let Eva.Cache_entry.Body f = Entry.statement entry in
    if Kernel_function.equal f (kf "copy") then begin
      let exit = List.map (fun (k, (s, _)) -> k, s) (Entry.exit entry) in
      ignore
        (Supplied.supply ~safety:(Entry.safety entry) f
           ~key:(Entry.key entry) ~input:(fst (Entry.input entry))
           ~footprint:(Entry.footprint entry) ~exit)
    end
  in
  List.iter by_hand produced;
  clear ();
  Eva.Parameters.Memexec.on ();
  Eva.Analysis.compute ();
  Format.printf "copy: hits %d, rejected for missing-part %d, \
                 for missing-points %d@."
    (hits "copy") (rejected "missing-part" "copy")
    (rejected "missing-points" "copy")

(* ----- Inout -------------------------------------------------------------- *)

let value_after stmt name =
  Results.(after stmt |> eval_var (global name) |> as_cvalue)
  |> one_line Cvalue.V.pretty

let functions = callees @ [ "deps_main"; "inout_main"; "main" ]

(* The callwise inputs and outputs at every call site, and those of every
   function, joined over its calls, as -inout prints them. *)
let inout_tables () =
  let at_calls f =
    List.map (fun stmt -> Inout.get_precise_inout ~stmt (kf f)) (calls f)
  in
  List.concat_map at_calls functions,
  List.map (fun f -> Inout.get_precise_inout (kf f)) functions

(* The actuals after the calls to narrow and narrow_and_write, and the
   tables of Inout. *)
let observe () =
  let narrow = List.hd (calls "narrow")
  and write = List.hd (calls "narrow_and_write") in
  (value_after narrow "g", value_after write "h"), inout_tables ()

let same_inout l l' =
  List.length l = List.length l' && List.for_all2 Inout_type.equal l l'

let inout () =
  let produced = first_analysis () in
  print_parts produced;
  let (g, h), fresh = observe () in
  Format.printf "caching disabled: g after narrow %s, h after \
                 narrow_and_write %s@." g h;
  second_analysis produced;
  Format.printf "hits: narrow %d, narrow_and_write %d@."
    (hits "narrow") (hits "narrow_and_write");
  let (g', h'), reused = observe () in
  Format.printf "after the hits: g after narrow %s, h after \
                 narrow_and_write %s@." g' h';
  Format.printf "callwise inputs and outputs equal at %d call sites: %b@."
    (List.length (fst fresh)) (same_inout (fst fresh) (fst reused));
  Format.printf "inputs and outputs equal for %d functions: %b@."
    (List.length (snd fresh)) (same_inout (snd fresh) (snd reused))

(* A premise of the supplier violated on purpose: the options of Eva differ
   between the analysis that produces the entries and the one that uses
   them. With -eva-no-results-function narrow in the using analysis only,
   the analysis of narrow with caching disabled saves no state at its
   statements, Inout gives Top as the result of its call, and the caller
   does not reduce g. The hit restores the Inout part of the producing
   analysis, and the caller reduces g. Nothing detects the difference. *)
let options () =
  let narrow = List.hd (calls "narrow") in
  let produced = first_analysis () in
  Eva.Parameters.NoResultsFunction.add
    (Kernel_function.get_definition (kf "narrow"));
  ignore (first_analysis ());
  let g = value_after narrow "g" in
  second_analysis produced;
  Format.printf "options differ: g after narrow: caching disabled %s; \
                 after %d hit %s@." g (hits "narrow") (value_after narrow "g")

(* The values at the end of copy that Eva prints with -eva, when an option
   that decides which states are saved is set in the analysis that produces
   the entries, in the one that uses them, or in both. The option is named
   by EVA_TEST_CACHE_PARTS_OPTION: results for -eva-no-results, function for
   -eva-no-results-function copy, domain for -eva-no-results-domain cvalue;
   the analyses by EVA_TEST_CACHE_PARTS_WHERE: producer, consumer or both.
   An analysis with caching disabled and the options of the using analysis
   runs first, for the comparison. The same option in the two analyses is the
   premise of the supplier; the other two cases violate it on purpose. *)
let saved_states () =
  let copy = Kernel_function.get_definition (kf "copy") in
  let set on =
    match Sys.getenv_opt "EVA_TEST_CACHE_PARTS_OPTION" with
    | Some "results" -> Eva.Parameters.ResultsAll.set (not on)
    | Some "function" ->
      Eva.Parameters.NoResultsFunction.clear ();
      if on then Eva.Parameters.NoResultsFunction.add copy
    | Some "domain" ->
      Eva.Parameters.NoResultsDomain.clear ();
      if on then Eva.Parameters.NoResultsDomain.add "cvalue"
    | _ -> ()
  in
  let where = Sys.getenv_opt "EVA_TEST_CACHE_PARTS_WHERE" in
  let producer = where = Some "producer" || where = Some "both" in
  let consumer = where = Some "consumer" || where = Some "both" in
  set consumer;
  Format.printf "caching disabled, with the options of the using analysis@.";
  ignore (first_analysis ());
  set producer;
  Format.printf "producing analysis@.";
  let produced = first_analysis () in
  set consumer;
  Format.printf "using analysis@.";
  second_analysis produced;
  Format.printf "hits: copy %d, rejected for missing-points %d@."
    (hits "copy") (rejected "missing-points" "copy")

(* ----- Checks of the assigns clauses -------------------------------------- *)

(* The assigns and from clauses of the contract of checked. *)
let clauses () =
  let f = kf "checked" in
  Property.ip_of_spec f Kglobal ~active:[] (Annotations.funspec f)
  |> List.filter
    (function Property.IPAssigns _ | Property.IPFrom _ -> true | _ -> false)

let print_statuses moment =
  List.iter
    (fun ip ->
       Format.printf "%s: %a: %a@." moment Property.short_pretty ip
         Property_status.pretty (Property_status.get ip))
    (clauses ())

(* A change of a correctness parameter of Eva removes the statuses emitted by
   Eva. The parameter is then set back to its value. *)
let remove_eva_statuses () =
  let name = "-eva-warn-pointer-subtraction" in
  let value = Dynamic.Parameter.Bool.get name () in
  Dynamic.Parameter.Bool.set name (not value);
  Dynamic.Parameter.Bool.set name value

(* -from-verify-assigns is set: the clauses of checked are checked in the
   first analysis. Their statuses are removed. A hit evaluates no clause:
   the part of From is not audited under this option, both calls to checked
   reject their candidates in the second analysis, and the analysis of the
   body checks the clauses again. *)
let verify () =
  let produced = first_analysis () in
  print_statuses "caching disabled";
  remove_eva_statuses ();
  print_statuses "statuses removed";
  second_analysis produced;
  Format.printf "checked: hits %d, rejected for callback %d@."
    (hits "checked") (rejected "callback" "checked");
  print_statuses "second analysis"

(* ----- Readers of the states saved at statements -------------------------- *)

let readers () =
  let produced = first_analysis () in
  second_analysis produced;
  let sum f = List.fold_left (fun acc callee -> acc + f callee) 0 callees in
  Format.printf "hits %d, rejected for consumer %d@."
    (sum hits) (sum (rejected "consumer"))

(* ----- Several visits of one body ----------------------------------------- *)

(* On visits.c, with -calldeps: the callwise dependencies at the call sites of
   choose, in an analysis with memexec, in an analysis with caching
   disabled, which produces the entries of choose, and in an analysis to
   which these entries are supplied. *)
let visits () =
  let print name table =
    List.iter
      (fun stmt ->
         Format.printf "%s: choose at line %d: %s@." name (line stmt)
           (one_line Eva.Assigns.pretty (List.assoc (Kstmt stmt) table)))
      (calls "choose")
  in
  clear ();
  Eva.Parameters.Memexec.on ();
  Eva.Analysis.compute ();
  let memexec = callwise_froms () in
  let memexec_hits =
    Eva.Statistics.(get memexec_hits) (kf "choose")
  in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced = Producer.entries (kf "choose") in
  let fresh = callwise_froms () in
  second_analysis produced;
  let reused = callwise_froms () in
  Format.printf "memexec hits: choose %d; supplied hits: choose %d@."
    memexec_hits (hits "choose");
  print "caching disabled" fresh;
  print "memexec" memexec;
  print "supplied hits" reused;
  Format.printf "equal to caching disabled: %b; equal to memexec: %b@."
    (same_froms fresh reused) (same_froms memexec reused)

(* ----- Logic inputs of an assertion that Eva does not evaluate ---------- *)

(* On logic.c, logic_loop.c and logic_wider.c, with -calldeps. Inout computes
   the logic inputs of the assertion of leaf from the address in p, which
   Eva does not read: the Inout part of an entry of leaf is withheld, and
   every candidate is rejected for missing-part. The logic inputs of each
   call site are then those of caching disabled. *)
let logic () =
  let f = kf "leaf" in
  let zones () =
    List.map
      (fun stmt ->
         line stmt,
         (Inout.get_precise_inout ~stmt f).Inout_type.over_logic_inputs)
      (calls "leaf")
  in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced = Producer.entries f in
  print_parts produced;
  let fresh = zones () in
  second_analysis produced;
  let reused = zones () in
  Format.printf "leaf: hits %d, rejected for missing-part %d@." (hits "leaf")
    (rejected "missing-part" "leaf");
  List.iter2
    (fun (line, zone) (_, zone') ->
       Format.printf "leaf at line %d: logic inputs %s; caching disabled %s@."
         line (one_line Memory_zone.pretty zone')
         (one_line Memory_zone.pretty zone))
    fresh reused;
  Format.printf "logic inputs equal to caching disabled: %b@."
    (List.for_all2 (fun (_, z) (_, z') -> Memory_zone.equal z z') fresh reused)

(* ----- Results by function after the hits -------------------------------- *)

(* The results by function of From and Inout are computed from the states
   saved at the statements of each function, and a hit saves none for the
   called function. After an analysis with hits, they are refused with a
   user error, whoever requests them. *)
let by_function () =
  List.map
    (fun f ->
       let kf = kf f in
       Format.asprintf "%s: from [%s]; inputs [%s]" f
         (one_line Eva.Assigns.pretty (From.get kf))
         (one_line Memory_zone.pretty (Inout.kf_inputs kf)))
    [ "copy"; "deps_main" ]

(* Runs [f] after the analysis with the supplied entries, once: the
   extensions of the main function also run after each -then. *)
let after_hits f =
  let ran = ref false in
  fun () ->
    if not !ran then begin
      ran := true;
      second_analysis (first_analysis ());
      Format.printf "hits: copy %d; statement results complete: %b@."
        (hits "copy") (Eva.Results.statement_results_complete ());
      f ()
    end

let refused name f =
  match f () with
  | _ -> Format.printf "%s: computed@." name
  | exception Log.AbortError _ -> Format.printf "%s: refused@." name

(* The requests of the module, through the API of From and Inout and through
   the dynamic access to Inout that Eva also uses. A later analysis with
   caching disabled gives the results by function again. *)
let api () =
  let produced = first_analysis () in
  let fresh = by_function () in
  second_analysis produced;
  Format.printf "hits: copy %d; statement results complete: %b@."
    (hits "copy") (Eva.Results.statement_results_complete ());
  let kf_outputs =
    Dynamic.get ~plugin:"Inout" "kf_outputs"
      Datatype.(func Kernel_function.ty Memory_zone.ty)
  in
  refused "From.get" (fun () -> From.get (kf "deps_main"));
  refused "Inout.kf_inputs" (fun () -> Inout.kf_inputs (kf "deps_main"));
  let call = List.hd (calls "copy") in
  refused "Inout.stmt_inputs" (fun () -> Inout.stmt_inputs call);
  refused "Inout.stmt_outputs" (fun () -> Inout.stmt_outputs call);
  refused "Inout.expr_inputs"
    (fun () ->
       match call.skind with
       | Instr (Call (_, _, arg :: _, _)) -> Inout.expr_inputs call arg
       | _ -> assert false);
  refused "Inout.kf_outputs, by the dynamic access"
    (fun () -> kf_outputs (kf "copy"));
  ignore (first_analysis ());
  Format.printf "after an analysis with caching disabled: statement results \
                 complete: %b; results by function equal: %b@."
    (Eva.Results.statement_results_complete ())
    (List.equal String.equal fresh (by_function ()))

(* The session after the hits is saved in the file named by
   EVA_TEST_CACHE_PARTS_SESSION, for another process to load. *)
let save () =
  Project.save (Filepath.of_string (Sys.getenv "EVA_TEST_CACHE_PARTS_SESSION"))

(* A copy of the project after the hits, made by Project.create_by_copy,
   carries the record of the functions answered by hits. *)
let copy_after_hits () =
  let copy = Project.create_by_copy ~last:false "after hits" in
  Project.on copy
    (fun () ->
       Format.printf "in the copy: statement results complete: %b@."
         (Eva.Results.statement_results_complete ());
       refused "in the copy: From.get" (fun () -> From.get (kf "deps_main")))
    ()

(* ----- Requests that start the analysis or read a memo ------------------ *)

(* From.get starts the analysis of Eva when its results are not computed.
   After the entries are supplied, the first request starts the analysis, in
   which the three calls to copy hit: this request is refused, as the second
   one. A later analysis with caching disabled gives the dependencies of the
   first analysis again. *)
let lazy_from () =
  let copy = kf "copy" in
  let produced = first_analysis () in
  let fresh = From.get copy in
  List.iter (fun p -> ignore (Supplied.supply_produced p)) produced;
  clear ();
  Eva.Parameters.Memexec.on ();
  refused "first request" (fun () -> From.get copy);
  Format.printf "hits: copy %d; statement results complete: %b@."
    (hits "copy") (Eva.Results.statement_results_complete ());
  refused "second request" (fun () -> From.get copy);
  ignore (first_analysis ());
  Format.printf "after an analysis with caching disabled: equal to the \
                 first analysis: %b@."
    (Eva.Assigns.equal fresh (From.get copy))

(* The outputs and inputs by function of copy requested at the start of the
   analysis with the supplied entries, before any hit. Inout does not start
   the analysis: the results of the analysis are not available yet, and each
   request computes its result from them and memoises it, as with caching
   disabled. After the hits, every request is refused, those memoised
   included. A later analysis with caching disabled gives the results of the
   first analysis again. *)
let warm () =
  let copy = kf "copy" in
  let requests =
    [ "Inout.kf_external_inputs", Inout.kf_external_inputs;
      "Inout.kf_external_outputs", Inout.kf_external_outputs;
      "Inout.kf_inputs", Inout.kf_inputs;
      "Inout.kf_outputs", Inout.kf_outputs ]
  in
  let ask moment =
    List.iter
      (fun (name, f) -> refused (moment ^ ": " ^ name) (fun () -> f copy))
      requests
  in
  let results () = List.map (fun (_, f) -> f copy) requests in
  let produced = first_analysis () in
  let fresh = results () in
  let early = ref true in
  Eva.Cvalue_callbacks.register_at_start_hook
    (fun () -> if !early then begin early := false; ask "at the start" end);
  second_analysis produced;
  Format.printf "hits: copy %d; statement results complete: %b@."
    (hits "copy") (Eva.Results.statement_results_complete ());
  ask "after the hits";
  ignore (first_analysis ());
  Format.printf "after an analysis with caching disabled: equal to the \
                 first analysis: %b@."
    (List.equal Memory_zone.equal fresh (results ()))

(* The results of an analysis, taken by Eva_results.get_results and installed
   by Eva_results.set_results, keep the record of the functions answered by
   hits. The results of the analysis with caching disabled and those of the
   analysis with hits are installed in turn. *)
let snapshot () =
  let copy = kf "copy" in
  let produced = first_analysis () in
  let fresh = From.get copy in
  let disabled = Eva.Eva_results.get_results () in
  second_analysis produced;
  let with_hits = Eva.Eva_results.get_results () in
  let install name results =
    Eva.Eva_results.set_results results;
    Format.printf "installed the results %s: statement results complete: \
                   %b@." name (Eva.Results.statement_results_complete ());
    match From.get copy with
    | deps ->
      Format.printf "From.get: equal to the first analysis: %b@."
        (Eva.Assigns.equal fresh deps)
    | exception Log.AbortError _ -> Format.printf "From.get: refused@."
  in
  install "with hits" with_hits;
  install "of caching disabled" disabled;
  install "with hits" with_hits

(* During the analysis with the supplied entries, after the first call to
   copy, which hits, a call hook of the test module adds copy to the option
   -eva-no-results-function. A change of an option of Eva clears the results
   of the analysis while it runs: the later calls to copy are not answered by
   entries produced with the former value. *)
let reset () =
  let copy = kf "copy" in
  let produced = first_analysis () in
  let changed = ref false in
  Eva.Cvalue_callbacks.register_call_hook ~cache_protocol:true
    (fun _callstack f _state _kind ->
       if not !changed && Kernel_function.equal f copy then begin
         changed := true;
         Eva.Parameters.NoResultsFunction.add
           (Kernel_function.get_definition copy)
       end);
  second_analysis produced;
  Format.printf "copy after the change: hits %d, rejected for \
                 analysis-reset %d@."
    (hits "copy") (rejected "analysis-reset" "copy")

(* ----- Values given in another project or for another callstack --------- *)

(* Three parts of this test, which no consumer needs. During each analysis of
   the body of copy, a value of each is given: for the callstack of the body
   in the current project, for the callstack of the caller and, with
   EVA_TEST_CACHE_PARTS_SWITCH set, for the same callstack while another
   project is current. Only the first one is kept with the entry. The change
   of the current project refuses the body of copy (see [Body_access]):
   then no entry of copy is produced. *)
let project () =
  let switch = Sys.getenv_opt "EVA_TEST_CACHE_PARTS_SWITCH" <> None in
  let register name =
    Eva.Cache_part.register ~name ~needed:(fun () -> false)
      ~restore:(fun _ _ _ () -> ()) ()
  in
  let kept = register "kept"
  and other_project = register "other-project"
  and caller = register "caller" in
  let other = Project.create "other" in
  let reads = Base.SetLattice.empty in
  let give callstack f _state results =
    match results with
    | `Body _ when Kernel_function.equal f (kf "copy") ->
      Eva.Cache_part.provide kept callstack ~reads ();
      if switch then
        Project.on other
          (Eva.Cache_part.provide other_project callstack ~reads) ();
      Option.iter
        (fun outer -> Eva.Cache_part.provide caller outer ~reads ())
        (Eva.Callstack.pop callstack)
    | _ -> ()
  in
  Eva.Cvalue_callbacks.register_call_results_hook ~cache_protocol:true give;
  print_parts (first_analysis ())

(* The entries produced in the current project, supplied to a copy of it:
   the functions of the copy are other values, and the supply refuses the
   entries. *)
let copied () =
  let produced = first_analysis () in
  let copy = Project.create_by_copy ~last:false "copied" in
  let supply () =
    match List.iter (fun p -> ignore (Supplied.supply_produced p)) produced
    with
    | () -> Format.printf "supplied to the copy@."
    | exception Invalid_argument msg -> Format.printf "refused: %s@." msg
  in
  Project.on copy supply ()

(* ----- Results of the analysis asked while it runs ---------------------- *)

(* On history.c, with -calldeps. During an analysis with caching disabled,
   at the end of each call of leaf, the test module asks the results of the
   analysis what From and Inout ask them: whether each statement is
   reachable, and the state at the start of leaf for the callstack of the
   call. Both answers are the same for every call. The analysis produces the
   entries of leaf; the first one is supplied to a second analysis, in which
   the first and third calls hit. The results of From and Inout at each call
   are compared with caching disabled. *)
let history () =
  let asking = ref true in
  Eva.Cvalue_callbacks.register_call_results_hook ~cache_protocol:true
    (fun callstack f _ results ->
       match results with
       | `Body ({ Eva.Cvalue_callbacks.before_stmts; _ }, _)
         when !asking && Kernel_function.get_name f = "leaf" ->
         let states = Lazy.force before_stmts in
         let reached s =
           match Cil_datatype.Stmt.Hashtbl.find_opt states s with
           | Some state -> Cvalue.Model.is_reachable state
           | None -> false
         in
         let unreached =
           List.filter (fun s -> not (reached s))
             (Kernel_function.get_definition f).sallstmts
         in
         let pre =
           Results.(at_start_of f |> in_callstack callstack |>
                    get_cvalue_model)
         in
         Format.printf "call of leaf: statements not reached %d, reachable \
                        in the results %d; state at the start: top %b@."
           (List.length unreached)
           (List.length (List.filter Results.is_reachable unreached))
           (Cvalue.Model.is_top pre)
       | _ -> ());
  let sites = calls "leaf" in
  let observe () =
    let froms = callwise_froms () in
    List.map
      (fun stmt ->
         List.assoc (Kstmt stmt) froms,
         Inout.get_precise_inout ~stmt (kf "leaf"))
      sites
  in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  asking := false;
  let produced = Producer.entries (kf "leaf") in
  print_parts produced;
  let fresh = observe () in
  second_analysis [ List.hd produced ];
  Format.printf "hits: leaf %d@." (hits "leaf");
  List.iter2
    (fun (stmt, (d, io)) (d', io') ->
       Format.printf "leaf at line %d: %s; equal to caching disabled: \
                      dependencies %b, inputs and outputs %b@."
         (line stmt) (one_line Eva.Assigns.pretty d)
         (Eva.Assigns.equal d d') (Inout_type.equal io io'))
    (List.combine sites (observe ())) fresh

(* ----- A body with a call ------------------------------------------------- *)

(* On nested.c, with -calldeps. The entries of outer, whose body calls
   inner, have no part: every candidate of outer is rejected and its calls
   are analysed, in which the calls to inner hit. unused is never called:
   its inputs are computed from the states saved at its statements, which
   is refused after the hits. *)
let nested () =
  let unused () = Inout.get_precise_inout (kf "unused") in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced =
    List.concat_map (fun f -> Producer.entries (kf f)) [ "inner"; "outer" ]
  in
  print_parts produced;
  refused "caching disabled: Inout.get_precise_inout of unused" unused;
  let fresh = callwise_froms () in
  second_analysis produced;
  Format.printf "inner: hits %d; outer: hits %d, rejected for missing-part \
                 %d@." (hits "inner") (hits "outer")
    (rejected "missing-part" "outer");
  Format.printf "callwise dependencies equal at %d call sites: %b@."
    (List.length fresh) (same_froms fresh (callwise_froms ()));
  refused "after the hits: Inout.get_precise_inout of unused" unused

(* On dead-call.c, with -calldeps. The body of leaf has a call under a
   condition that the call of leaf does not meet. From and Inout give their
   parts for the calls of the body that the analysis recorded, none here:
   the entry of leaf has both parts. The lookup rejects it
   (nested-delivery), since the body has a call, and the body is
   analysed. *)
let dead_call () =
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced = Producer.entries (kf "leaf") in
  print_parts produced;
  let fresh = callwise_froms () in
  second_analysis produced;
  Format.printf "leaf: hits %d, rejected for nested-delivery %d@."
    (hits "leaf") (rejected "nested-delivery" "leaf");
  Format.printf "callwise dependencies equal at %d call sites: %b@."
    (List.length fresh) (same_froms fresh (callwise_froms ()))

(* On nested.c. The inputs and outputs of unused, which no call reaches,
   requested at the start of the analysis with the supplied entries. Inout
   then starts an analysis of the program, here with -deps set: every
   candidate is rejected (consumer), the results are complete, and the
   request computes the result of unused from the states saved at its
   statements and memoises it. -deps is unset before the analysis goes on
   and takes hits. After the hits, the request is refused, the memoised
   result included; the results of inner, joined from those of its calls,
   are not. *)
let fallback () =
  let unused () = Inout.get_precise_inout (kf "unused") in
  let inner () = Inout.get_precise_inout (kf "inner") in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced =
    List.concat_map (fun f -> Producer.entries (kf f)) [ "inner"; "outer" ]
  in
  let fresh = inner () in
  let early = ref true in
  Eva.Cvalue_callbacks.register_at_start_hook
    (fun () ->
       if !early then begin
         early := false;
         Dynamic.Parameter.Bool.on "-deps" ();
         refused "at the start, with -deps: Inout.get_precise_inout of unused"
           unused;
         Dynamic.Parameter.Bool.off "-deps" ()
       end);
  second_analysis produced;
  Format.printf "inner: hits %d; statement results complete: %b@."
    (hits "inner") (Eva.Results.statement_results_complete ());
  refused "after the hits: Inout.get_precise_inout of unused" unused;
  Format.printf "after the hits: Inout.get_precise_inout of inner equal to \
                 caching disabled: %b@." (Inout_type.equal fresh (inner ()))

(* On nested.c. The three requests of Inout on the external view of a
   function that test their refusal before a table of their own: the
   dereferenced zones (-deref), the operational inputs without the formals
   and with them (-inout). Each is made as in the scenario above, at the
   start of the analysis with -deps, which fills its table, then after the
   hits: the request is refused, the result memoised before the hits
   included. *)
let external_requests () =
  let requests =
    [ "the dereferenced zones of inner",
      (fun () -> Inout__Derefs.compute_external (kf "inner"));
      "the operational inputs of unused",
      (fun () -> ignore (Inout__Operational_inputs.get_external (kf "unused")));
      "the operational inputs of unused with its formals",
      (fun () ->
         let pretty =
           Inout__Operational_inputs
           .pretty_operational_inputs_external_with_formals
         in
         ignore (Format.asprintf "%a" pretty (kf "unused"))) ]
  in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced =
    List.concat_map (fun f -> Producer.entries (kf f)) [ "inner"; "outer" ]
  in
  let early = ref true in
  Eva.Cvalue_callbacks.register_at_start_hook
    (fun () ->
       if !early then begin
         early := false;
         Dynamic.Parameter.Bool.on "-deps" ();
         List.iter
           (fun (name, f) -> refused ("at the start, with -deps: " ^ name) f)
           requests;
         Dynamic.Parameter.Bool.off "-deps" ()
       end);
  second_analysis produced;
  Format.printf "inner: hits %d; statement results complete: %b@."
    (hits "inner") (Eva.Results.statement_results_complete ());
  List.iter (fun (name, f) -> refused ("after the hits: " ^ name) f) requests

(* The results of Eva at the first statement of copy, read directly, which
   no reader of this test refuses: whether it is reached, and the value of
   the formal src there. *)
let raw () =
  let first = List.hd (Kernel_function.get_definition (kf "copy")).sallstmts in
  let src =
    List.find (fun vi -> vi.vname = "src")
      (Kernel_function.get_formals (kf "copy"))
  in
  let print name =
    Format.printf "%s: first statement of copy reachable: %b; src: %s@." name
      (Eva.Results.is_reachable first)
      (Results.(before first |> eval_var src |> as_cvalue)
       |> one_line Cvalue.V.pretty)
  in
  let produced = first_analysis () in
  print "caching disabled";
  second_analysis produced;
  print "after the hits"

(* A plug-in that reads the states saved at the statements, loaded after the
   hits: the lookup has not seen it. The requests of the results at a
   statement or at the start of a function, answered before it is loaded,
   are refused afterwards, in the project, in a copy of it and once the
   results with hits are installed again; the results of the analysis with
   caching disabled, installed in between, are given. Occurrence is the
   plug-in loaded. *)
let late_reader () =
  let copy = kf "copy" in
  let first = List.hd (Kernel_function.get_definition copy).sallstmts in
  let produced = first_analysis () in
  let disabled = Eva.Eva_results.get_results () in
  second_analysis produced;
  let with_hits = Eva.Eva_results.get_results () in
  let requests moment =
    let request name f = refused (moment ^ ": " ^ name) f in
    request "state before a statement"
      (fun () -> ignore Results.(before first |> get_cvalue_model));
    request "state after a statement"
      (fun () -> ignore Results.(after first |> get_cvalue_model));
    request "state at the start of a function"
      (fun () -> ignore Results.(at_start_of copy |> get_cvalue_model));
    request "states by callstack"
      (fun () -> ignore Results.(before first |> by_callstack));
    request "callstacks of a statement"
      (fun () -> ignore Results.(before first |> callstacks));
    (* The request of the engine, which no code of the tree calls. *)
    request "callstacks of a statement, from the engine"
      (fun () ->
         let module Engine = (val Eva__Private.Engine.current ()) in
         ignore (Engine.callstacks (Before first)));
    request "reachability of a statement"
      (fun () -> ignore (Results.is_reachable first));
    request "initial state"
      (fun () -> ignore Results.(at_start |> get_cvalue_model))
  in
  Format.printf "hits: copy %d; statement results complete: %b@."
    (hits "copy") (Eva.Results.statement_results_complete ());
  requests "after the hits";
  Dynamic.load_plugin "occurrence";
  requests "with a reader loaded";
  let project = Project.create_by_copy ~last:false "after hits" in
  Project.on project requests "in a copy";
  Eva.Eva_results.set_results disabled;
  requests "results of caching disabled installed";
  Eva.Eva_results.set_results with_hits;
  requests "results with hits installed";
  let project = Project.create_by_copy ~last:false "installed" in
  Project.on project requests "in a copy of the installed results"

(* ----- Clients that a hit runs ------------------------------------------- *)

(* A part of this test, needed in both analyses, whose value is given for
   every body analysed: the entries carry it. With
   EVA_TEST_CACHE_PARTS_AUDITED set, the part is registered as audited. *)
let unaudited_part () =
  let audited = Sys.getenv_opt "EVA_TEST_CACHE_PARTS_AUDITED" <> None in
  let part =
    Eva.Cache_part.register ~name:"test" ~needed:(fun () -> true)
      ~audited:(fun () -> audited) ~restore:(fun _ _ _ () -> ()) ()
  in
  let give callstack _kf _state = function
    | `Body _ ->
      Eva.Cache_part.provide part callstack ~reads:Base.SetLattice.empty ()
    | _ -> ()
  in
  Eva.Cvalue_callbacks.register_call_results_hook ~cache_protocol:true give;
  second_analysis (first_analysis ());
  Format.printf "copy: hits %d, rejected for callback %d@."
    (hits "copy") (rejected "callback" "copy")

(* A client of the hook of Inout on the inputs and outputs of each call,
   registered through its dynamic access without an audit. *)
let inout_client () =
  let register =
    Dynamic.get ~plugin:"Inout" "register_call_hook"
      Datatype.(func (func Inout_type.ty unit) unit)
  in
  register (fun _ -> ());
  second_analysis (first_analysis ());
  Format.printf "copy: hits %d, rejected for callback %d@."
    (hits "copy") (rejected "callback" "copy")

(* A predicate that the lookup evaluates is client code. The predicate is
   the predicate [needed] of a part never needed and not audited, or with
   EVA_TEST_CACHE_PARTS_CARRIER=reader the predicate of a reader of the
   statement states, which never reads. At its n-th evaluation in the second
   analysis, n given by EVA_TEST_CACHE_PARTS_ARM, it registers a client that
   is not audited, given by EVA_TEST_CACHE_PARTS_CLIENT:
   - eva (default): a call hook of Eva, which counts the calls it receives
     with [`Reuse];
   - inout: a client of the hook of Inout on the inputs and outputs of each
     call, through its dynamic access, which counts the calls it receives
     after a hit on copy;
   - part: a part never needed. *)
let predicate () =
  let arm =
    Option.fold ~none:1 ~some:int_of_string
      (Sys.getenv_opt "EVA_TEST_CACHE_PARTS_ARM")
  in
  let client =
    Option.value ~default:"eva" (Sys.getenv_opt "EVA_TEST_CACHE_PARTS_CLIENT")
  in
  let armed = ref false and evaluations = ref 0 in
  let reused = ref 0 and after_hit = ref 0 in
  let count_reuse _callstack _kf _state = function
    | `Reuse -> incr reused
    | _ -> ()
  in
  let register_client () =
    match client with
    | "eva" -> Eva.Cvalue_callbacks.register_call_hook count_reuse
    | "inout" ->
      let register =
        Dynamic.get ~plugin:"Inout" "register_call_hook"
          Datatype.(func (func Inout_type.ty unit) unit)
      in
      register (fun _ -> if hits "copy" > 0 then incr after_hit)
    | "part" ->
      ignore
        (Eva.Cache_part.register ~name:"late" ~needed:(fun () -> false)
           ~restore:(fun _ _ _ () -> ()) ())
    | _ -> failwith ("unknown client " ^ client)
  in
  let predicate () =
    if !armed then begin
      incr evaluations;
      if !evaluations = arm then register_client ()
    end;
    false
  in
  begin match Sys.getenv_opt "EVA_TEST_CACHE_PARTS_CARRIER" with
    | Some "reader" ->
      Eva.Cache_part.register_state_reader ~name:"predicate" predicate
    | _ ->
      ignore
        (Eva.Cache_part.register ~name:"predicate" ~needed:predicate
           ~restore:(fun _ _ _ () -> ()) ())
  end;
  let produced = first_analysis () in
  armed := true;
  second_analysis produced;
  Format.printf "copy: hits %d, rejected for callback %d@."
    (hits "copy") (rejected "callback" "copy");
  match client with
  | "eva" ->
    Format.printf "hook: %d calls with Reuse; predicate evaluated %d times@."
      !reused !evaluations
  | "inout" ->
    Format.printf "inout client: %d calls after a hit on copy@." !after_hit
  | _ -> ()

(* A subscriber of the statistics by function of the summary, which a hit
   updates after its delivery, as the end of an analysis of the body does.
   For each update of the statistics of copy, it records whether the
   results at the statements are complete and the number of statements of
   copy reached. With EVA_TEST_CACHE_PARTS_AUDITED set, it is registered as
   audited. *)
let stats () =
  let audited = Sys.getenv_opt "EVA_TEST_CACHE_PARTS_AUDITED" <> None in
  let updates = ref [] in
  let observe = function
    | State_builder.Update (f, (stats : Eva__Private.Summary.fun_stats))
      when Kernel_function.get_name f = "copy" ->
      let complete = Eva.Results.statement_results_complete () in
      updates := (complete, stats.fun_coverage.reachable) :: !updates
    | _ -> ()
  in
  Eva__Private.Summary.FunctionStats.add_hook_on_change ~audited observe;
  let print analysis =
    let pretty (complete, reached) =
      Printf.sprintf "complete %b, reached %d" complete reached
    in
    Format.printf "updates of copy, %s: %s@." analysis
      (String.concat "; " (List.rev_map pretty !updates));
    updates := []
  in
  let produced = first_analysis () in
  print "caching disabled";
  second_analysis produced;
  print "second analysis";
  Format.printf "copy: hits %d, rejected for callback %d@."
    (hits "copy") (rejected "callback" "copy")

(* The summary installs once what a hit runs after its delivery. Another
   installation, through the internal modules of Eva, is refused, and the
   hits run what the summary installed. *)
let replace_summary () =
  let replaced _kf = Format.printf "replaced function run@." in
  begin
    match
      Eva__Private.Safety_delivery.on_delivered
        ~unaudited_subscribers:(fun () -> false) replaced
    with
    | () -> Format.printf "installed a second function@."
    | exception Invalid_argument msg -> Format.printf "refused: %s@." msg
  end;
  second_analysis (first_analysis ());
  Format.printf "copy: hits %d@." (hits "copy")

(* ----- Call of the entry point ------------------------------------------ *)

(* The cell in which the hook of Inout leaves the inputs and outputs of the
   last call, for the caller to reduce its actuals. The entry point has no
   caller: after its call, analysed or answered by a hit, the cell is
   empty. *)
let root () =
  let cell () =
    match Eva__Transfer_stmt.current_kf_inout () with
    | None -> "empty"
    | Some _ -> "filled"
  in
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced = Producer.entries (kf "main") in
  Format.printf "caching disabled: entries of main %d, Inout cell %s@."
    (List.length produced) (cell ());
  second_analysis produced;
  Format.printf "second analysis: hits of main %d, Inout cell %s@."
    (hits "main") (cell ())

(* ----- Names of the parts ------------------------------------------------- *)

(* A second part named as a registered one: the name is the key of a
   part. *)
let duplicate () =
  match
    Eva.Cache_part.register ~name:"from" ~needed:(fun () -> false)
      ~restore:(fun _ _ _ () -> ()) ()
  with
  | _ -> Format.printf "registered a second part named from@."
  | exception Invalid_argument msg -> Format.printf "refused: %s@." msg

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_PARTS" with
  | Some "from" -> Boot.Main.extend from
  | Some "missing" -> Boot.Main.extend missing
  | Some "both" -> Boot.Main.extend both
  | Some "inout" -> Boot.Main.extend inout
  | Some "options" -> Boot.Main.extend options
  | Some "saved-states" -> Boot.Main.extend saved_states
  | Some "verify" -> Boot.Main.extend verify
  | Some "readers" -> Boot.Main.extend readers
  | Some "project" -> Boot.Main.extend project
  | Some "copied" -> Boot.Main.extend copied
  | Some "api" -> Boot.Main.extend api
  | Some "then" -> Boot.Main.extend (after_hits ignore)
  | Some "save" -> Boot.Main.extend (after_hits save)
  | Some "copy" -> Boot.Main.extend (after_hits copy_after_hits)
  | Some "visits" -> Boot.Main.extend visits
  | Some "logic" -> Boot.Main.extend logic
  | Some "history" -> Boot.Main.extend history
  | Some "nested" -> Boot.Main.extend nested
  | Some "dead-call" -> Boot.Main.extend dead_call
  | Some "fallback" -> Boot.Main.extend fallback
  | Some "external" -> Boot.Main.extend external_requests
  | Some "raw" -> Boot.Main.extend raw
  | Some "late-reader" -> Boot.Main.extend late_reader
  | Some "lazy-from" -> Boot.Main.extend lazy_from
  | Some "warm" -> Boot.Main.extend warm
  | Some "snapshot" -> Boot.Main.extend snapshot
  | Some "reset" -> Boot.Main.extend reset
  | Some "duplicate" -> Boot.Main.extend duplicate
  | Some "unaudited-part" -> Boot.Main.extend unaudited_part
  | Some "inout-client" -> Boot.Main.extend inout_client
  | Some "predicate" -> Boot.Main.extend predicate
  | Some "stats" -> Boot.Main.extend stats
  | Some "replace-summary" -> Boot.Main.extend replace_summary
  | Some "root" -> Boot.Main.extend root
  | _ -> ()
