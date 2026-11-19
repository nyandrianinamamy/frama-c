(* Test module of cache-safety.t: delivers the Safety part of an entry at a
   hit, then prints the statuses, the red contexts and the values at the end
   of main. Summary lines start with "| " and are sorted, so that run.t can
   compare two runs. *)

open Cil_types

module Supplied = Eva.Supplied_entries
module Producer = Eva.Cache_producer
module Entry = Eva.Cache_entry.Cvalue
module Results = Eva.Results

let kf = Globals.Functions.find_by_name

let global name = Globals.Vars.find_from_astinfo name Global

let formal f name =
  List.find (fun vi -> vi.vname = name) (Kernel_function.get_formals (kf f))

let env name = Sys.getenv_opt ("EVA_TEST_CACHE_SAFETY_" ^ name)

(* ----- Summary of an analysis -------------------------------------------- *)

let pretty_emitted fmt (status : Property_status.emitted_status) =
  Format.pp_print_string fmt
    (match status with
     | True -> "valid"
     | False_if_reachable -> "invalid"
     | False_and_reachable -> "invalid and reachable"
     | Dont_know -> "unknown")

let pretty_status fmt = function
  | Property_status.Never_tried -> Format.pp_print_string fmt "never tried"
  | Inconsistent _ -> Format.pp_print_string fmt "inconsistent"
  | Best (status, _) -> pretty_emitted fmt status

(* An alarm by its name, other properties by their short form. *)
let pretty_property fmt ip =
  match ip with
  | Property.IPCodeAnnot { ica_ca; _ } when Alarms.find ica_ca <> None ->
    let alarm = Option.get (Alarms.find ica_ca) in
    Format.fprintf fmt "alarm %s" (Alarms.get_name alarm)
  | _ -> Property.short_pretty fmt ip

(* Every property with a status, at its location. *)
let statuses () =
  let line ip =
    Format.asprintf "%a: status of %a: %a" Fileloc.pretty
      (Property.location ip) pretty_property ip
      pretty_status (Property_status.get ip)
  in
  let lines = ref [] in
  Property_status.iter (fun ip ->
      match Property_status.get ip with
      | Never_tried -> ()
      | Best _ | Inconsistent _ -> lines := line ip :: !lines);
  !lines

let pretty_kinstr fmt = function
  | Kglobal -> Format.pp_print_string fmt "global"
  | Kstmt stmt -> Fileloc.pretty fmt (Cil_datatype.Stmt.loc stmt)

(* A callstack with its call sites, latest call first. *)
let pretty_callstack fmt = function
  | None -> Format.pp_print_string fmt "no callstack"
  | Some (callstack : Eva.Callstack.t) ->
    let pretty_call fmt (kf, stmt) =
      Format.fprintf fmt "%a :: %a <- " Kernel_function.pretty kf
        Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
    in
    List.iter (pretty_call fmt) callstack.stack;
    Kernel_function.pretty fmt callstack.entry_point

(* Every red context, with its callstack. *)
let red_contexts () =
  let target = function
    | Eva__Red_statuses.Alarm alarm -> "alarm " ^ Alarms.get_name alarm
    | Prop ip -> Format.asprintf "%a" pretty_property ip
  in
  let add kinstr t callstacks lines =
    let line callstack =
      Format.asprintf "%a: red context of %s in %a" pretty_kinstr kinstr
        (target t) pretty_callstack callstack
    in
    List.map line callstacks @ lines
  in
  Eva__Red_statuses.fold_contexts add []

(* The value of [name] at the end of the entry point. *)
let value name =
  let main = fst (Globals.entry_point ()) in
  let request = Results.at_end_of main in
  let main = Kernel_function.get_name main in
  match Results.(eval_var (global name) request |> as_integer) with
  | Ok n -> Format.asprintf "end of %s: %s = %a" main name Z.pp_print n
  | Error e ->
    Format.asprintf "end of %s: %s: %a" main name Results.pretty_error e

let summary names =
  let lines = statuses () @ red_contexts () @ List.map value names in
  List.iter (Format.printf "| %s@.") (List.sort_uniq String.compare lines)

let hits name =
  Format.printf "hits on %s: %d@." name
    (Eva.Statistics.get Eva.Statistics.cache_hits (kf name))

(* The code annotation [name] of [f], as a property. *)
let annotation f name =
  let found = ref None in
  Annotations.iter_all_code_annot (fun stmt _ ca ->
      match ca.annot_content with
      | AAssert (_, { tp_statement = { pred_name; _ }; _ })
        when List.mem name pred_name
          && Kernel_function.equal
               (Kernel_function.find_englobing_kf stmt) (kf f) ->
        found := Some (Property.ip_of_code_annot_single (kf f) stmt ca)
      | _ -> ());
  Option.get !found

(* ----- Settings and observations of an analysis -------------------------- *)

let red_hook_calls = ref 0

(* The calls of the observer of the kernel registered by [register_client]
   while a hit on body or on pre delivers: after the visits of the
   function were recorded as skipped for body, whose Safety part registers
   an alarm, and before for pre, whose preconditions are evaluated before. *)
let observer_calls = ref 0

let visits_skipped name =
  match Globals.Functions.find_by_name name with
  | f -> Eva__Safety_delivery.visits_skipped f
  | exception Not_found -> false

let hits_on name =
  match Globals.Functions.find_by_name name with
  | f -> Eva.Statistics.get Eva.Statistics.cache_hits f
  | exception Not_found -> 0

let count_in_delivery () =
  if visits_skipped "body"
  || hits_on "pre" > 0 && not (visits_skipped "pre")
  then incr observer_calls

(* An observer of the reads of the metadata of allocated blocks, which runs
   the observer that it replaces. *)
let observe_metadata ~audited =
  let previous = ref None in
  let observer base =
    count_in_delivery ();
    Option.iter (fun f -> f base) !previous
  in
  previous := Base.observe_metadata_reads ~audited (Some observer)

(* A client of one of the hooks that a hit runs, or that an analysis of a
   body runs and a hit does not. None of them is audited, but the observers
   whose name ends with -audited. *)
let register_client = function
  | "call" -> Eva.Cvalue_callbacks.register_call_hook (fun _ _ _ _ -> ())
  | "call-results" ->
    Eva.Cvalue_callbacks.register_call_results_hook (fun _ _ _ _ -> ())
  | "statement" ->
    Eva__Cvalue_callbacks.register_statement_hook (fun _ _ _ -> ())
  | "red" -> Eva__Red_statuses.register_hook ignore
  | "status" -> Property_status.register_status_update_hook (fun _ _ _ -> ())
  | "property" -> Property_status.register_property_add_hook ignore
  | "annotations" -> Annotations.add_hook_on_change ignore
  | "listener" -> Log.add_listener ignore
  | "register" -> Kernel.register Log.Warning ignore
  | "history" ->
    Log.on_history_access
      (fun ~plugin:_ ~kind:_ ~category:_ ~once_category:_ -> ())
  | "messages" -> Messages.add_hook ignore
  | "opaque" -> Hook.Opaque.on_call count_in_delivery
  | "opaque-audited" -> Hook.Opaque.on_call ~audited:true count_in_delivery
  | "metadata" -> observe_metadata ~audited:false
  | "metadata-audited" -> observe_metadata ~audited:true
  | "validity" ->
    ignore (Base.observe_validity_updates (Some (fun _ ~weak:_ -> ())))
  | "origin" -> Origin.on_history_access ignore
  | "daemon" -> ignore (Async.on_progress ignore)
  | "location" -> Current_loc.add_hook_on_change ignore
  | "perf" -> Eva.Eva_perf.StatByCallstack.add_hook_on_change ignore
  | "safety-result" -> Eva.Safety_part.on_result (fun _ _ -> ())
  | "reach-result" -> Eva.Reach_part.on_result (fun _ _ -> ())
  | "collector-result" -> Eva.Body_access.on_result (fun _ _ -> ())
  | client -> failwith ("unknown client " ^ client)

let set_category directive =
  Format.printf "a hook sets %s@." directive;
  Dynamic.Parameter.String.set "-eva-warn-key" directive

(* A client of the hooks of red statuses that adds a red status of its own,
   to the check never of body, at its first call in each analysis. *)
let add_own_red_status () =
  let inside = ref false in
  Eva__Red_statuses.register_hook (fun _ ->
      incr red_hook_calls;
      if not !inside then begin
        inside := true;
        Eva__Red_statuses.add_red_property Kglobal (annotation "body" "never");
        inside := false
      end)

(* Applied before the analysis that uses the entry, and before the reference
   analysis, according to the environment:
   - ALARM=S: option -eva-warn-key alarm=S, for instance abort, or active
     after a first analysis with the category inactive, which prints no
     message of the category and so leaves none for the rule that prints a
     text once;
   - CATEGORY=K=S: option -eva-warn-key K=S;
   - HOOK=K=S: option -eva-warn-key K=S, set by a hook at the first call of
     body, after the lookup of a candidate entry for that call;
   - STOP=N: option -eva-stop-at-nth-alarm N;
   - OVERFLOW=on: option -warn-signed-overflow;
   - COUNT=red: counts the calls of the hook of red statuses;
   - SERVER=late: loads the server plug-in, which registers a client of the
     hooks on the changes of annotations, audited for the lookup but run
     through [Hook.Opaque.wrap];
   - CLIENT=C: registers a client of the hook C (see [register_client]);
   - ROUTE=R: a client sets signed-overflow to abort: a hook of red
     statuses (R=red), a hook on the status of the instance of a
     precondition at line 18 (R=pre), or a listener of the line of a call
     answered by a hit (R=log);
   - UNDO=1: a hook of red statuses sets signed-overflow to inactive;
   - ALARM2=1: a hook of red statuses sets alarm to abort at its second
     call;
   - OWNRED=1: a client of the hooks of red statuses adds a red status of
     its own (see [add_own_red_status]). *)
let setup () =
  if env "SERVER" = Some "late" then Dynamic.load_plugin "server";
  Option.iter register_client (env "CLIENT");
  (match env "ROUTE" with
   | Some "red" ->
     Eva__Red_statuses.register_hook
       (fun _ -> set_category "signed-overflow=abort")
   | Some "pre" ->
     let line stmt =
       Filepos.line (Fileloc.start_pos (Cil_datatype.Stmt.loc stmt))
     in
     Property_status.register_status_update_hook (fun _ ip _ ->
         match ip with
         | Property.IPPropertyInstance { ii_stmt; _ } when line ii_stmt = 18 ->
           set_category "signed-overflow=abort"
         | _ -> ())
   | Some "log" ->
     Log.add_listener ~plugin:"eva" (fun e ->
         let text = String.trim (Rich_text.plain e.Log.evt_message) in
         if String.starts_with ~prefix:"call to body: lookup: hit" text
         then set_category "signed-overflow=abort")
   | _ -> ());
  if env "UNDO" = Some "1" then
    Eva__Red_statuses.register_hook (fun _ ->
        Dynamic.Parameter.String.set "-eva-warn-key"
          "signed-overflow=inactive");
  if env "ALARM2" = Some "1" then begin
    let calls = ref 0 in
    Eva__Red_statuses.register_hook (fun _ ->
        incr calls;
        if !calls = 2 then set_category "alarm=abort")
  end;
  if env "OWNRED" = Some "1" then add_own_red_status ();
  Option.iter (Dynamic.Parameter.String.set "-eva-warn-key") (env "CATEGORY");
  Option.iter (fun directive ->
      let set = ref false in
      Eva.Cvalue_callbacks.register_call_hook (fun _ called _ _ ->
          if not !set && Kernel_function.equal called (kf "body") then begin
            set := true;
            Dynamic.Parameter.String.set "-eva-warn-key" directive
          end))
    (env "HOOK");
  Option.iter
    (fun s -> Dynamic.Parameter.String.set "-eva-warn-key" ("alarm=" ^ s))
    (env "ALARM");
  Option.iter (fun n -> Eva.Parameters.StopAtNthAlarm.set (int_of_string n))
    (env "STOP");
  if env "OVERFLOW" = Some "on" then Kernel.SignedOverflow.on ();
  if env "COUNT" = Some "red" then
    Eva__Red_statuses.register_hook (fun _ -> incr red_hook_calls)

(* Runs the analysis. An abort ends it, and the summary describes the tables
   at that point. With HISTORY=count, prints the number of consultations of
   the history of the logger that the observer of the collector saw during
   the analysis. *)
let analyse () =
  let before = Eva__Body_access.history_consultations () in
  (try Eva.Analysis.compute ()
   with Log.AbortError _ -> Format.printf "analysis aborted@.");
  if env "HISTORY" = Some "count" then
    Format.printf "history consultations: %d@."
      (Eva__Body_access.history_consultations () - before)

(* With EXPORT=on, the annotations that Eva.Export generates in [body] after
   the analysis. Eva gives each of them a valid status. *)
let export () =
  if env "EXPORT" = Some "on" then begin
    let fundec = Kernel_function.get_definition (kf "body") in
    ignore (Visitor.visitFramacFunction (Eva.Export.generator ()) fundec);
    let count = ref 0 in
    List.iter (fun stmt ->
        List.iter (fun ca ->
            incr count;
            Format.printf "exported at %a: %a@." Fileloc.pretty
              (Cil_datatype.Stmt.loc stmt) Printer.pp_code_annotation ca)
          (Annotations.code_annot ~emitter:Eva.Export.emitter stmt))
      fundec.sallstmts;
    Format.printf "annotations exported in body: %d@." !count
  end

let observations ?(called = "body") () =
  if env "COUNT" = Some "red" || env "OWNRED" = Some "1" then
    Format.printf "red hook calls: %d@." !red_hook_calls;
  Option.iter (fun client ->
      let rejected =
        Eva.Statistics.get (Eva.Statistics.cache_rejected "callback")
          (kf called)
      in
      let hits = Eva.Statistics.get Eva.Statistics.cache_hits (kf called) in
      Format.printf "client %s: hits on %s: %d, rejected for callback: %d@."
        client called hits rejected;
      if List.mem client
          [ "opaque"; "opaque-audited"; "metadata"; "metadata-audited" ]
      then
        Format.printf "observer calls during a delivery: %d@."
          !observer_calls)
    (env "CLIENT");
  if env "STOP" <> None then
    Format.printf "cache-rejected-stop-at-nth-alarm of body: %d@."
      (Eva.Statistics.get
         (Eva.Statistics.cache_rejected "stop-at-nth-alarm") (kf "body"));
  export ()

(* ----- Modes ------------------------------------------------------------- *)

(* Caching disabled: neither memexec nor supplied entries. Prints the
   Safety part of each analysed call of [observed]. *)
let reference ?observed names () =
  Option.iter (fun name ->
      Eva.Safety_part.on_result (fun callstack safety ->
          if Kernel_function.equal (Eva.Callstack.top_kf callstack) (kf name)
          then
            Format.printf "Safety part of %a: %a@." pretty_callstack
              (Some callstack) Eva.Safety_part.pretty safety))
    observed;
  setup ();
  Eva.Parameters.Memexec.off ();
  analyse ();
  observations ();
  summary names

let one_line write =
  let buffer = Buffer.create 80 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 1000;
  Format.fprintf fmt "%a@?" Eva.Safety_part.pretty_write write;
  Buffer.contents buffer

(* A first analysis, from the entry point of the command line, stores the
   entry of [body], if any, whose Safety part is printed. Changing the entry
   point to [main] then resets the analysis with its alarms and statuses. *)
let produce_and_reset main =
  Eva.Analysis.compute ();
  let produced =
    match Producer.entries (kf "body") with
    | [produced] -> Some produced
    | [] -> Format.printf "no entry produced for body@."; None
    | _ -> assert false
  in
  Option.iter (fun produced ->
      let safety = Entry.safety (Producer.cache_entry produced) in
      List.iter (fun w -> Format.printf "safety: %s@." (one_line w)) safety)
    produced;
  Kernel.MainFunction.set main;
  assert (not (Eva.Analysis.is_computed ()));
  Format.printf "after the reset: %d statuses, %d red contexts@."
    (List.length (statuses ())) (List.length (red_contexts ()));
  produced

(* Whether a hit answered a call of [body] in the analysis, then whether
   the record remains after a change of the entry point resets the
   analysis. *)
let skipped_after_reset () =
  let skipped () = Eva__Safety_delivery.visits_skipped (kf "body") in
  Format.printf "visits skipped in body: %b@." (skipped ());
  Kernel.MainFunction.set "producer";
  assert (not (Eva.Analysis.is_computed ()));
  Format.printf "visits skipped in body after the reset: %b@." (skipped ())

(* Supplies the [produced] entry of [body]; with PART=drop, by hand, with
   its Safety part and without its Reach part, which the lookup rejects. *)
let supply produced =
  if env "PART" = Some "drop" then
    let e = Producer.cache_entry produced in
    ignore
      (Supplied.supply ~safety:(Entry.safety e) (kf "body") ~key:(Entry.key e)
         ~input:(fst (Entry.input e)) ~footprint:(Entry.footprint e)
         ~exit:(List.map (fun (k, (s, _)) -> k, s) (Entry.exit e)))
  else ignore (Supplied.supply_produced produced)

(* The entry of [body] is supplied to a second analysis, from the function
   named by MAIN, main by default. *)
let replay names () =
  let main = Option.value ~default:"main" (env "MAIN") in
  let produced = produce_and_reset main in
  setup ();
  Option.iter supply produced;
  Format.printf "second analysis@.";
  analyse ();
  hits "body";
  observations ();
  summary names;
  skipped_after_reset ()

(* The last call of [body] in [caller]. *)
let call_of_body caller =
  let calls = Kernel_function.find_syntactic_callsites (kf "body") in
  let in_caller (k, _) = Kernel_function.equal k (kf caller) in
  match List.rev (List.sort compare (List.filter in_caller calls)) with
  | (_, stmt) :: _ -> stmt
  | [] -> assert false

(* The callstack of the last call of [body] in main. *)
let at_hit () =
  Eva.Callstack.init ~thread:Eva.Thread.main_id ~entry_point:(kf "main")
  |> Eva.Callstack.push (kf "body") (call_of_body "main")

(* The Safety part of the entry of [body] is delivered outside any analysis:
   twice for the call of [body] at line 26 of main, then its red contexts,
   with the call of [body] in [outer] as frame, for a callstack of
   [outer]. *)
let deliver () =
  let produced = Option.get (produce_and_reset "main") in
  let safety = Entry.safety (Producer.cache_entry produced) in
  let at_hit = at_hit () in
  let tables () = List.sort compare (statuses () @ red_contexts ()) in
  Eva__Safety_delivery.deliver at_hit safety;
  let once = tables () in
  Eva__Safety_delivery.deliver at_hit safety;
  Format.printf "a second delivery changes nothing: %b@." (once = tables ());
  let with_frame : Eva.Safety_part.write -> _ = function
    | Red_context r ->
      Some (Eva.Safety_part.Red_context
              { r with frames = [kf "body", call_of_body "outer"] })
    | _ -> None
  in
  let thread = Eva.Thread.main_id in
  let from_outer = Eva.Callstack.init ~thread ~entry_point:(kf "outer") in
  Eva__Safety_delivery.deliver from_outer (List.filter_map with_frame safety);
  summary []

(* Another emitter registers the alarms of the entry of [body] first. Then
   the entry is delivered at the call at line 26 (OWNER=deliver), or main is
   analysed with caching disabled (OWNER=analyse). With OWNER=late, the
   entry is delivered first, and the other emitter registers the alarms
   after it. Prints the emitter that owns each alarm and the status of each
   emitter on it. *)
let owner () =
  let produced = Option.get (produce_and_reset "main") in
  let safety = Entry.safety (Producer.cache_entry produced) in
  let other =
    Emitter.create "Other" [ Emitter.Alarm; Emitter.Property_status ]
      ~correctness:[] ~tuning:[]
  in
  let register_other () =
    List.iter (function
        | Eva.Safety_part.Emitted_alarm { kinstr; alarm; _ } ->
          ignore (Alarms.register other kinstr alarm)
        | _ -> ())
      safety
  in
  if env "OWNER" <> Some "late" then register_other ();
  if List.mem (env "OWNER") [ Some "deliver"; Some "late" ]
  then Eva__Safety_delivery.deliver (at_hit ()) safety
  else begin
    Eva.Parameters.Memexec.off ();
    Eva.Analysis.compute ()
  end;
  if env "OWNER" = Some "late" then register_other ();
  Alarms.iter (fun emitter kf stmt ~rank:_ alarm ca ->
      let ip = Property.ip_of_code_annot_single kf stmt ca in
      let by_emitter (e : Property_status.emitter_with_properties) status acc =
        Format.asprintf "%a %a" Emitter.Usable_emitter.pretty e.emitter
          pretty_emitted status :: acc
      in
      let emitted = Property_status.fold_on_statuses by_emitter ip [] in
      Format.printf "| alarm %s at %a: owner %a; statuses: %s@."
        (Alarms.get_name alarm) Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
        Emitter.pretty emitter
        (String.concat ", " (List.sort compare emitted)))

(* Runs [f] the first time the statement hooks run for a statement of
   body. The client is registered as classified, as the collector admits
   it: a change of project that it makes is seen by the comparisons of the
   project alone, and not by the refusal of opaque clients. *)
let at_first_statement_of_body f =
  let entered = ref false in
  Eva__Cvalue_callbacks.register_statement_hook ~classified:true
    (fun callstack _stmt _states ->
       if not !entered
       && Kernel_function.equal (Eva.Callstack.top_kf callstack) (kf "body")
       then begin
         entered := true;
         f ()
       end)

(* A client of the statement hooks enters another project the first time it
   runs in body, and adds a red context there. *)
let enter_other_project () =
  let other = Project.create_by_copy ~last:false "other" in
  at_first_statement_of_body (fun () ->
      Project.on other (fun () ->
          let body = kf "body" in
          let first = Kernel_function.find_first_stmt body in
          Eva__Red_statuses.add_red_property Kglobal
            (Property.ip_reachable_stmt body first)) ())

(* An analysis from producer, with the hook above. The entries of [body] it
   stores, if any, are supplied to an analysis from main. *)
let crossing () =
  enter_other_project ();
  Eva.Analysis.compute ();
  List.iter (fun name ->
      Format.printf "collector-refused-project-switch of %s: %d@." name
        (Eva.Statistics.get
           (Eva.Statistics.collector_refused "project-switch") (kf name)))
    [ "body"; "producer" ];
  let produced = Producer.entries (kf "body") in
  Format.printf "entries produced for body: %d@." (List.length produced);
  List.iter (fun p ->
      List.iter (fun w -> Format.printf "safety: %s@." (one_line w))
        (Entry.safety (Producer.cache_entry p)))
    produced;
  Kernel.MainFunction.set "main";
  List.iter (fun p -> ignore (Supplied.supply_produced p)) produced;
  Eva.Analysis.compute ();
  summary ["r1"; "r2"]

let crossing_reference () =
  enter_other_project ();
  reference ["r1"; "r2"] ()

(* Runs [analyse] in a hook of the change of the current project, to a copy
   of the first project. The kernel runs no hook of the change of project
   for a change made during such a hook. The first time it runs in body, a
   client of the statement hooks enters the first project with Project.on,
   and leaves it.
   Then prints the number of statuses and red contexts of the first
   project. *)
let reentrant analyse () =
  let first = Project.current () in
  let other = Project.create_by_copy ~last:false "other" in
  let started = ref false in
  Project.register_after_set_current_hook ~user_only:false (fun _ ->
      if not !started then begin
        started := true;
        at_first_statement_of_body (fun () ->
            Project.on first (fun () ->
                Format.printf "entered the first project: %b@."
                  (Project.is_current first)) ());
        analyse ()
      end);
  Project.set_current other;
  Project.on first (fun () ->
      Format.printf "| first project: %d statuses, %d red contexts@."
        (List.length (statuses ())) (List.length (red_contexts ()))) ()

(* In the copy, an analysis from producer, then an analysis from main with
   the entries of [body] that the first one stored. *)
let reentrant_replay () =
  Eva.Analysis.compute ();
  List.iter (fun name ->
      Format.printf "collector-refused-project-switch of %s: %d@." name
        (Eva.Statistics.get
           (Eva.Statistics.collector_refused "project-switch") (kf name)))
    [ "body"; "producer" ];
  let produced = Producer.entries (kf "body") in
  Format.printf "entries produced for body: %d@." (List.length produced);
  Kernel.MainFunction.set "main";
  List.iter (fun p -> ignore (Supplied.supply_produced p)) produced;
  Eva.Analysis.compute ();
  summary ["r1"; "r2"]

(* An entry for [outer], whose body calls [body]. *)
let nested () =
  let input = Cvalue.Model.empty_map in
  let none = Base.Hptset.empty in
  let footprint =
    Supplied.{ read = none; written = none; written_exit = none;
               written_sure = none }
  in
  match
    Supplied.supply (kf "outer") ~key:none ~input ~footprint
      ~exit:[Supplied.empty_key, input]
  with
  | _ -> Format.printf "entry for outer supplied@."
  | exception Invalid_argument msg -> Format.printf "refused: %s@." msg

(* The Safety part of each analysed call of [parent], which calls [child]:
   in a first analysis, which analyses [child], then in a second one, where
   a hit on the entry of [child] produced by the first analysis answers the
   call. *)
let enclosing () =
  let parent = kf "parent" and child = kf "child" in
  Eva.Safety_part.on_result ~audited:true (fun callstack safety ->
      if Kernel_function.equal (Eva.Callstack.top_kf callstack) parent then
        match safety with
        | [] -> Format.printf "Safety part of parent: none@."
        | writes ->
          List.iter
            (fun w -> Format.printf "Safety part of parent: %s@." (one_line w))
            writes);
  Eva.Analysis.compute ();
  let produced =
    match Producer.entries child with
    | [produced] -> produced
    | _ -> assert false
  in
  ignore (Supplied.supply_produced produced);
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ();
  Format.printf "second analysis@.";
  Eva.Analysis.compute ();
  hits "child"

let bases vis =
  List.fold_left
    (fun acc vi -> Base.Hptset.add (Base.of_varinfo vi) acc)
    Base.Hptset.empty vis

let state bindings =
  let bind acc (vi, n) =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    let v = Cvalue.V.inject_int (Z.of_int n) in
    let v = Cvalue.V_Or_Uninitialized.initialized v in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size acc
  in
  List.fold_left bind Cvalue.Model.empty_map bindings

(* Prints the status of the check [one] of [pre] once main is analysed,
   before the passes that run at the end of the analysis. *)
let observe_one () =
  let one = annotation "pre" "one" in
  Eva.Safety_part.on_result ~audited:true (fun callstack _ ->
      if Kernel_function.equal (Eva.Callstack.top_kf callstack) (kf "main")
      then
        Format.printf "before the passes: one is %a@." pretty_status
          (Property_status.get one))

(* The Reach part of an analysis of [pre] from x = 1, written by hand: the
   four statements of the body are reached, the then branch of the
   condition is taken, and x is read at the assignment and at the
   condition, where out is written. The body of [pre] is the same in
   precondition.c, pre-route.c and metadata.c, at other lines: the
   statements are found by their kind and by their line relative to the
   assignment. *)
let precondition_reach ~x ~out =
  let module Reach = Eva.Reach_part in
  let line s = Filepos.line (Fileloc.start_pos (Cil_datatype.Stmt.loc s)) in
  let stmts = (Kernel_function.get_definition (kf "pre")).sallstmts in
  let is_set = function Instr (Set _) -> true | _ -> false in
  let first = line (List.find (fun s -> is_set s.skind) stmts) in
  let stmt is_kind l =
    List.find (fun s -> line s = first + l && is_kind s.skind) stmts
  in
  let set = stmt is_set 0 in
  let cond = stmt (function If _ -> true | _ -> false) 1 in
  let skip = stmt (function Instr (Skip _) -> true | _ -> false) 2 in
  let return = stmt (function Return _ -> true | _ -> false) 4 in
  let point p = Reach.Reached { point = p; frames = [] } in
  let reached s =
    [ point (Eva__Domain_store.Before s); point (Eva__Domain_store.After s) ]
  in
  let zones stmt read write =
    Reach.Zones { stmt; frames = []; read; write }
  in
  let x = Locations.zone_of_varinfo x in
  let out = Locations.zone_of_varinfo out in
  Reach.part ~points:true
    (List.concat_map reached [ set; cond; skip; return ]
     @ [ Reach.Guard { stmt = cond; outcome = true };
         zones set x out; zones cond x Memory_zone.bottom ])

(* A hand-written entry of [pre] for x = 1. The requires clause belongs to
   the call site: the entry neither reads g nor carries its status. Its
   Safety part gives the check [one] a valid status, as an analysis of the
   body from x = 1 does. *)
let precondition () =
  setup ();
  let x = formal "pre" "x" and out = global "out" in
  let written = bases [out] in
  let safety =
    [ Eva.Safety_part.Emitted_status
        { property = annotation "pre" "one"; status = True;
          emitter = Eva.Analysis.emitter; frames = [] } ]
  in
  let reach = precondition_reach ~x ~out in
  ignore
    (Supplied.supply ~safety ~reach (kf "pre")
       ~key:(bases [x])
       ~input:(state [x, 1])
       ~footprint:Supplied.{ read = bases [x]; written;
                             written_exit = written; written_sure = written }
       ~exit:[Supplied.empty_key, state [x, 1; out, 2]]);
  observe_one ();
  analyse ();
  hits "pre";
  observations ~called:"pre" ();
  summary ["out"]

let precondition_reference () =
  observe_one ();
  reference ~observed:"pre" ["out"] ()

(* Within one analysis: a hand-written entry of body for x = 5 makes the
   analysis use supplied entries. Once, when the check trigger of other is
   evaluated, a client supplies the entries that the analysis stored for
   the first call of body, with SUPPLY=on only, and with NEXT=1 a copy of
   each, written by hand with its Safety and Reach parts, which carries no
   status of the warning categories. Then it sets the category
   signed-overflow to abort, or with TRIGGER=red applies the settings of
   [setup]. The client is a hook on the statuses of properties by default,
   a hook of red statuses with TRIGGER=red, and with TRIGGER=observer an
   observer of the Safety part of the analysed calls, which runs at the end
   of the analysis of other and which no hit runs. *)
let same_analysis () =
  let x = formal "body" "x" and out = global "out" in
  let written = bases [out] in
  if env "SUPPLY" = Some "on" then
    ignore
      (Supplied.supply (kf "body") ~key:(bases [x]) ~input:(state [x, 5])
         ~footprint:Supplied.{ read = bases [x]; written;
                               written_exit = written; written_sure = written }
         ~exit:[Supplied.empty_key, state [x, 5; out, 12]])
  else Eva.Parameters.Memexec.off ();
  let copy produced =
    let e = Producer.cache_entry produced in
    ignore
      (Supplied.supply ~safety:(Entry.safety e) ?reach:(Entry.reach e)
         (kf "body") ~key:(Entry.key e)
         ~input:(fst (Entry.input e)) ~footprint:(Entry.footprint e)
         ~exit:(List.map (fun (k, (s, _)) -> k, s) (Entry.exit e)))
  in
  let fired = ref false in
  let fire () =
    if not !fired then begin
      fired := true;
      if env "SUPPLY" = Some "on" then begin
        let produced = Producer.entries (kf "body") in
        Format.printf "supplied during the analysis: %d@."
          (List.length produced);
        List.iter (fun p ->
            ignore (Supplied.supply_produced p);
            if env "NEXT" = Some "1" then copy p)
          produced
      end;
      if env "TRIGGER" = Some "red" then setup ()
      else Dynamic.Parameter.String.set "-eva-warn-key" "signed-overflow=abort"
    end
  in
  let trigger = annotation "other" "trigger" in
  (match env "TRIGGER" with
   | Some "red" ->
     Eva__Red_statuses.register_hook (function
         | Prop ip when Property.equal ip trigger -> fire ()
         | Prop _ | Alarm _ -> ())
   | Some "observer" ->
     (* Registered as audited, which it is not: it supplies entries and
        changes a setting. The scenario tests the check of the warning
        categories, which does not rely on the audit. *)
     Eva.Safety_part.on_result ~audited:true (fun callstack _ ->
         if Kernel_function.equal (Eva.Callstack.top_kf callstack) (kf "other")
         then fire ())
   | _ ->
     Property_status.register_status_update_hook (fun _ ip _ ->
         if Property.equal ip trigger then fire ()));
  analyse ();
  hits "body";
  summary ["out"]

(* The count of the changes of the current project made by operations of
   the kernel. *)
let project_count () =
  let show name f =
    let n = Project.current_changes () in
    f ();
    Format.printf "%s: %d@." name (Project.current_changes () - n)
  in
  let first = Project.current () in
  let other = Project.create "other" in
  show "set_current of the current project"
    (fun () -> Project.set_current first);
  show "copy" (fun () -> Project.copy ~selection:State_selection.empty other);
  show "on, left by an exception"
    (fun () -> try Project.on other (fun () -> raise Exit) () with Exit -> ());
  Project.set_current other;
  show "remove of the current project" (fun () -> Project.remove ());
  let file = Filepath.of_string "projects.sav" in
  Project.save_all file;
  show "load_all of two projects" (fun () -> Project.load_all file)

(* Two projects are saved, then loaded. During the loading, a hook of the
   change of project makes current again the project that was current
   before the last change; the loading then removes that project from the
   top of the stack of projects, and another one is current. *)
let load_hook () =
  let file = Filepath.of_string "two.sav" in
  ignore (Project.create "other");
  Project.save_all file;
  let loaded = ref 0 and seen = ref None in
  Project.register_after_load_hook (fun _ -> incr loaded);
  Project.register_after_set_current_hook ~user_only:false (fun old ->
      if !loaded = 2 && not (Project.is_current old) then begin
        Project.set_current old;
        seen := Some (Project.current (), Project.current_changes ())
      end);
  Project.load_all file;
  match !seen with
  | None -> Format.printf "the hook made no change@."
  | Some (project, count) ->
    Format.printf "after the loading: same project %b, same count %b@."
      (Project.is_current project) (count = Project.current_changes ())

(* With OWNRED=producer, a client of the hooks of red statuses, registered
   before any analysis, adds a red status of its own to the check never of
   body during the analysis from producer only. *)
let () =
  if env "OWNRED" = Some "producer" then begin
    let inside = ref false in
    Eva__Red_statuses.register_hook (fun _ ->
        incr red_hook_calls;
        if not !inside && Kernel.MainFunction.get () = "producer" then begin
          inside := true;
          Eva__Red_statuses.add_red_property Kglobal
            (annotation "body" "never");
          inside := false
        end)
  end

(* ----- The registry of the audited observers of Base ---------------------- *)

(* Installs an audited observer of the reads of the metadata that holds 64
   KiB, and removes it. The observer is reachable from [cells] only, which
   holds it weakly. *)
let[@inline never] install_and_remove cells index =
  let payload = Bytes.make 65536 'x' in
  let observer (_ : Base.t) =
    ignore (Sys.opaque_identity (Bytes.get payload 0))
  in
  Weak.set cells index (Some observer);
  ignore (Base.observe_metadata_reads ~audited:true (Some observer));
  ignore (Base.observe_metadata_reads None)

(* The registry of the audited observers keeps no observer alive, and keeps
   the rule on the functions installed again: an audited function installed
   again without the flag does not count, another function installed without
   the flag counts, also once removed. *)
let registry () =
  let count = 128 in
  let cells = Weak.create count in
  for i = 0 to count - 1 do install_and_remove cells i done;
  Gc.full_major ();
  Gc.full_major ();
  let alive = ref 0 in
  for i = 0 to count - 1 do if Weak.check cells i then incr alive done;
  Format.printf "audited observers removed and still alive: %d of %d@."
    !alive count;
  let unaudited () = Base.has_unaudited_observers () in
  Format.printf "after them, an observer that is not audited: %b@."
    (unaudited ());
  let kept (_ : Base.t) = ignore (Sys.opaque_identity cells) in
  ignore (Base.observe_metadata_reads ~audited:true (Some kept));
  ignore (Base.observe_metadata_reads None);
  ignore (Base.observe_metadata_reads (Some kept));
  ignore (Base.observe_metadata_reads None);
  Format.printf "after an audited observer installed again without the \
                 flag: %b@." (unaudited ());
  let other (_ : Base.t) = ignore (Sys.opaque_identity count) in
  ignore (Base.observe_metadata_reads (Some other));
  Format.printf "after another observer installed without the flag: %b@."
    (unaudited ());
  ignore (Base.observe_metadata_reads None);
  Format.printf "after its removal: %b@." (unaudited ())

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_SAFETY" with
  | Some "replay" -> Boot.Main.extend (replay ["r1"; "r2"])
  | Some "replay-out" -> Boot.Main.extend (replay ["out"])
  | Some "deliver" -> Boot.Main.extend deliver
  | Some "reference" -> Boot.Main.extend (reference ["r1"; "r2"])
  | Some "reference-out" -> Boot.Main.extend (reference ["out"])
  | Some "precondition" -> Boot.Main.extend precondition
  | Some "precondition-reference" -> Boot.Main.extend precondition_reference
  | Some "crossing" -> Boot.Main.extend crossing
  | Some "crossing-reference" -> Boot.Main.extend crossing_reference
  | Some "owner" -> Boot.Main.extend owner
  | Some "same" -> Boot.Main.extend same_analysis
  | Some "reentrant" -> Boot.Main.extend (reentrant reentrant_replay)
  | Some "reentrant-reference" ->
    Boot.Main.extend (reentrant (reference ["r1"; "r2"]))
  | Some "nested" -> Boot.Main.extend nested
  | Some "enclosing" -> Boot.Main.extend enclosing
  | Some "project-count" -> Boot.Main.extend project_count
  | Some "load-hook" -> Boot.Main.extend load_hook
  | Some "registry" -> Boot.Main.extend registry
  | _ -> ()
