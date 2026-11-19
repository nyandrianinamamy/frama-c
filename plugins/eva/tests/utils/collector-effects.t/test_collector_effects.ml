module Access = Eva__Body_access
module Observation = Eva.Body_access
module Producer = Eva.Cache_producer
module Entry = Eva.Cache_entry.Cvalue
module State = Eva__Cvalue_domain.State
module Lookup = Eva__Supplied_entries.Lookup (struct
    type t = State.t
    let structure = Eva__Abstract.Domain.Leaf (State.key, (module State))
  end)

let name = Kernel_function.get_name

let reason result expected =
  assert (Access.verdict result = Error expected);
  Access.Result.refusal_id expected

let observe stack (result : Access.Result.t) =
  let function_name = name (Eva.Callstack.top_kf stack) in
  match function_name with
  | "count" | "count_y" ->
    let generation = Option.get result.hint_generation in
    assert (Access.verdict result = Ok ());
    Format.printf "%s generation %d, would-store@."
      function_name (Observation.hint_generation_number generation)
  | "discover" ->
    Format.printf "discover %s@." (reason result Observation.Widening_hint)
  | "start_recursion" ->
    let functions = List.map (fun (f, mode) -> name f, mode)
        result.used_functions in
    assert (List.sort compare functions =
            ["recur", `Body; "start_recursion", `Body]);
    Format.printf "trace includes recur and start_recursion@."
  | "outer_after_hit" ->
    let functions = List.map (fun (f, _) -> name f) result.used_functions in
    assert (List.sort compare functions =
            ["middle"; "outer_after_hit"; "threaded"]);
    Format.printf "trace through memexec hit includes threaded@."
  | "outer" ->
    let functions = List.map (fun (f, mode) -> name f, mode)
        result.used_functions in
    assert (List.sort compare functions =
            ["middle", `Body; "outer", `Body; "threaded", `Body]);
    Format.printf "trace includes the transitive call to threaded@."
  | _ -> ()

let kf = Globals.Functions.find_by_name

let check_escape model holder =
  let loc = Locations.of_base holder in
  let value = Cvalue.Model.find_indeterminate model loc in
  assert (not (Cvalue.V_Or_Uninitialized.is_noesc value));
  assert (Cvalue.V.is_bottom (Cvalue.V_Or_Uninitialized.get_v value))

let stack kf = Eva.Callstack.init ~thread:Eva.Thread.main_id ~entry_point:kf

let push callee caller =
  Eva.Callstack.push callee
    (Kernel_function.find_first_stmt (Eva.Callstack.top_kf caller)) caller

let global name =
  Base.of_varinfo (Globals.Vars.find_from_astinfo name Cil_types.Global)

let capture stack f =
  let output, result = Access.capture stack f in
  output, Option.get result

let check_lookup label stack input rejected hit =
  let result = Lookup.find stack input in
  let hit_id = Option.map (fun (entry, _) -> Entry.id entry) result.hit in
  assert (result.rejected = rejected && hit_id = hit);
  let report (id, reason) =
    Format.sprintf "%d:%s" id (Eva__Supplied_entries.rejection_id reason)
  in
  Format.printf "%s rejected=[%s] hit=%s@." label
    (String.concat "," (List.map report result.rejected))
    (Option.fold ~none:"none" ~some:string_of_int hit_id);
  result.hit

let supply produced = ignore (Eva.Supplied_entries.supply_produced produced)

let observe_sweep stack (result : Access.Result.t) =
  if name (Eva.Callstack.top_kf stack) = "swept" then begin
    let targets = Base.Hptset.elements result.sweeps in
    assert (List.map (Format.asprintf "%a" Base.pretty) targets = ["local"]);
    let holder = Base.of_varinfo (Globals.Vars.find_from_astinfo
                                    "holder" Cil_types.Global) in
    assert (Base.SetLattice.mem holder result.exit_writes);
    assert (Access.verdict result = Ok ());
    Format.printf
      "swept records local and the holder written by its scope exit@."
  end

let sweep_check () =
  let checking = ref true in
  Observation.on_result ~audited:true (fun stack result ->
      if !checking then observe_sweep stack result);
  Eva.Analysis.compute ();
  checking := false;
  let f = kf "swept" in
  let produced = List.hd (Producer.entries f) in
  let entry = Producer.cache_entry produced in
  let holder = global "holder" in
  List.iter (fun (_, (exit, _)) -> check_escape exit holder) (Entry.exit entry);
  let caller = push f (stack (kf "call_swept")) in
  let initial = Entry.input entry in
  supply produced;
  supply produced;
  let hit = check_lookup "clear" caller initial [] (Some 1) in
  let _, states = Option.get hit in
  List.iter (fun (_, (exit, _)) -> check_escape exit holder) states;
  let untouched = global "untouched" in
  assert (not (Base.Hptset.mem untouched (Entry.key entry)));
  let targets = Producer.sweeps produced in
  let swept = Base.Hptset.choose targets in
  let model, clob = initial in
  let cell ~escaping value =
    Cvalue.V_Or_Uninitialized.make ~initialized:true ~escaping value
  in
  let check label ~escaping value rejected hit =
    let cell = cell ~escaping value in
    let input = Cvalue.Model.add_indeterminate_binding ~exact:true model
        (Locations.of_base untouched) cell in
    ignore (check_lookup label caller (input, clob) rejected hit);
    input
  in
  let refused = [1, `Sweep; 2, `Sweep] in
  let ptr = Cvalue.V.inject swept (Ival.inject_range (Some Z.one) None) in
  let input = check "offset-range" ~escaping:false ptr refused None in
  let garbled = Cvalue.V.topify Origin.Arith ptr in
  ignore (check "garbled" ~escaping:false garbled refused None);
  ignore (check "unknown-bases" ~escaping:false Cvalue.V.top refused None);
  let changed, swept_value =
    Cvalue.V_Or_Uninitialized.unspecify_escaping_locals ~exact:true
      (Base.equal swept) (cell ~escaping:false Cvalue.V.top)
  in
  assert (changed && not (Cvalue.V_Or_Uninitialized.is_noesc swept_value));
  assert (Cvalue.V.get_bases (Cvalue.V_Or_Uninitialized.get_v swept_value)
          = Base.SetLattice.top);
  Format.printf "unknown-base sweep keeps all bases and marks escaping@.";
  ignore (check "escaping-plus-pointer" ~escaping:true ptr refused None);
  ignore (check "escaping-marker-alone" ~escaping:true Cvalue.V.bottom []
            (Some 1));
  let prebound =
    Cvalue.Model.add_binding ~exact:true model (Locations.of_base swept)
      Cvalue.V.singleton_zero
  in
  ignore (check_lookup "prebound" caller (prebound, clob)
            [1, `Key_differs; 2, `Key_differs] None);
  let check_producing_input label entry expected =
    let admitted, result = capture caller (fun () ->
        let admitted = Access.sweep ~owner:f ~inner:true targets model in
        Access.check_written ~entry ~exits:[];
        admitted)
    in
    assert admitted;
    assert (Access.verdict result = expected);
    Format.printf "producing input %s: %s@." label
      (Result.fold ~ok:(fun () -> "clear") ~error:Access.Result.refusal_id
         expected)
  in
  check_producing_input "clear" model (Ok ());
  check_producing_input "holder" input (Error Observation.Sweep);
  check_producing_input "prebound" prebound (Error Observation.Sweep);
  let owner = kf "callee" in
  let fundec = Kernel_function.get_definition owner in
  let outer = Base.of_varinfo (List.hd fundec.sbody.blocals) in
  let admitted, result = capture (stack owner) (fun () ->
      Access.sweep ~owner ~inner:false (Base.Hptset.singleton outer) model)
  in
  assert (not admitted);
  Format.printf "own outer scope: %s@." (reason result Observation.Sweep);
  let other = Project.create_by_copy ~last:false "other-watch" in
  Project.on other (fun () ->
      Kernel.MainFunction.set "start_watchpoint";
      Eva.Analysis.compute ();
      assert (Eva__Builtins_watchpoint.active ())) ();
  ignore (check_lookup "watch in another project" caller initial
            [1, `Watchpoint; 2, `Watchpoint] None)

let hint_lookup () =
  let f = kf "count" in
  let analyze () =
    Eva.Analysis.compute ();
    let generation e =
      Observation.hint_generation_number
        (Option.get (Producer.hint_generation e))
    in
    List.sort (fun a b -> Int.compare (generation a) (generation b))
      (Producer.entries f)
  in
  let initial, caller =
    match analyze () with
    | [a; b] ->
      List.iter supply [a; b];
      Entry.input (Producer.cache_entry b), push f (stack (kf "main"))
    | _ -> assert false
  in
  let check_trace hit =
    let entry, _ = Option.get hit in
    let dependencies = Option.get (Entry.dependencies entry) in
    match dependencies.used_functions with
    | [callee, `Body] ->
      assert (Kernel_function.equal callee f);
      Format.printf "supplied hit trace: %s (body), nonrecursive@."
        (name callee)
    | _ -> assert false
  in
  check_trace (check_lookup "newer generation" caller initial
                 [1, `Hint_generation] (Some 2));
  ignore (check_lookup "recursive stack" (push f caller) initial
            [1, `Recursion; 2, `Recursion] None);
  Project.clear ~selection:(State_selection.with_dependencies Eva.Analysis.self)
    ();
  List.iter supply (analyze ());
  check_trace (check_lookup "newer run" caller initial
                 [1, `Hint_generation; 2, `Hint_generation; 3, `Hint_generation]
                 (Some 4));
  let _, result = capture caller (fun () ->
      Access.read_widening_hints ();
      Eva__Widen_generation.advance ())
  in
  Format.printf "generation changed in reader: %s@."
    (reason result Observation.Widening_hint)

let trace_stack_check () =
  let owner = kf "outer" in
  let caller = stack owner in
  let middle = kf "middle" in
  let _, result = capture caller (fun () ->
      Access.include_trace (push middle caller)
        { functions = [middle, `Body; owner, `Body]; recursive = false })
  in
  Format.printf "included hit trace conflicts with caller: %s@."
    (reason result Observation.Recursion)

let install_watch_check () =
  Eva.Analysis.compute ();
  let module Builtins = Eva__Builtins in
  let _, install, _ =
    Option.get (Builtins.find_builtin_override (kf "Frama_C_watch_value"))
  in
  let entry = Producer.cache_entry (List.hd (Producer.entries (kf "swept"))) in
  let stmt = Kernel_function.find_first_stmt (kf "install_watchpoint") in
  let expr = Cil.integer ~loc:(Cil_datatype.Stmt.loc stmt) 0 in
  let arg value = Eva__Eva_ast.translate_exp expr, value in
  let ptr = Cvalue.V.inject (global "flag") Ival.zero in
  let int x = Cvalue.V.inject_int (Z.of_int x) in
  let args = [arg ptr; arg (int 4); arg (int 17); arg (int 0)] in
  let _, result = capture (stack (kf "install_watchpoint")) (fun () ->
      install (fst (Entry.input entry)) args)
  in
  assert (Eva__Builtins_watchpoint.active ());
  Format.printf "watch installation without statement transfer: %s@."
    (reason result Observation.Watchpoint)

let check_client target install =
  let calls = ref 0 in
  install (fun () -> incr calls);
  Observation.on_result ~audited:true (fun stack result ->
      if name (Eva.Callstack.top_kf stack) = target then
        Format.printf "%s: %s@." target (reason result Observation.Callback));
  Boot.Main.extend (fun () ->
      Eva.Analysis.compute ();
      assert (!calls = 1);
      assert (Producer.entries (kf target) = []);
      Format.printf "%s client calls: %d, entries: 0@." target !calls)

let raise_alarm_threshold event =
  if event.Log.evt_category = Some "alarm" then begin
    Eva.Parameters.StopAtNthAlarm.set max_int;
    Format.printf "listener raised stop threshold@."
  end

let () =
  match Sys.getenv_opt "EVA_TEST_COLLECTOR_EFFECTS" with
  | Some "sweep" -> Boot.Main.extend sweep_check
  | Some "hint-lookup" -> Boot.Main.extend hint_lookup
  | Some "trace-stack" -> Boot.Main.extend trace_stack_check
  | Some "watch-install" -> Boot.Main.extend install_watch_check
  | Some "red-client" ->
    check_client "alarm" (fun called ->
        Eva__Red_statuses.register_hook (fun _ -> called ()))
  | Some "history-client" ->
    check_client "swept" (fun called ->
        Log.on_history_access (fun ~plugin ~kind:_ ~category ~once_category:_ ->
            if plugin = "eva" && category = Some "locals-escaping"
            then called ()))
  | Some "raise-threshold" ->
    Log.add_listener ~plugin:"eva" ~kind:[Log.Warning] raise_alarm_threshold
  | Some "logger" ->
    Log.add_listener ~plugin:"eva" ~kind:[Log.Warning] ignore
  | _ -> Observation.on_result ~audited:true observe
