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
  | "swept" ->
    let targets = Base.Hptset.elements result.sweeps in
    assert (List.map (Format.asprintf "%a" Base.pretty) targets = ["local"]);
    let holder = Base.of_varinfo (Globals.Vars.find_from_astinfo
                                    "holder" Cil_types.Global) in
    assert (Base.SetLattice.mem holder result.exit_writes);
    assert (Access.verdict result = Ok ());
    Format.printf "swept records local and the holder written by its scope exit@."
  | _ -> ()

let kf = Globals.Functions.find_by_name

let check_escape model holder =
  let loc = Locations.of_base holder in
  let value = Cvalue.Model.find_indeterminate model loc in
  assert (not (Cvalue.V_Or_Uninitialized.is_noesc value));
  assert (Cvalue.V.is_bottom (Cvalue.V_Or_Uninitialized.get_v value))

let sweep_check () =
  Eva.Analysis.compute ();
  let f = kf "swept" in
  let produced = List.hd (Producer.entries f) in
  let entry = Producer.cache_entry produced in
  let holder = Base.of_varinfo (Globals.Vars.find_from_astinfo
                                  "holder" Cil_types.Global) in
  List.iter (fun (_, (exit, _)) -> check_escape exit holder) (Entry.exit entry);
  let caller = kf "call_swept" in
  let at = Kernel_function.find_first_stmt caller in
  let stack = Eva.Callstack.init ~thread:Eva.Thread.main_id ~entry_point:caller in
  let stack = Eva.Callstack.push f at stack in
  let initial = Entry.input entry in
  ignore (Eva.Supplied_entries.supply_produced produced);
  let result = Lookup.find stack initial in
  let _, states, _ = Option.get result.hit in
  List.iter (fun (_, (exit, _)) -> check_escape exit holder) states;
  let untouched = Base.of_varinfo (Globals.Vars.find_from_astinfo
                                     "untouched" Cil_types.Global) in
  assert (not (Base.Hptset.mem untouched (Entry.key entry)));
  let swept = Base.Hptset.choose (Producer.sweeps produced) in
  let ptr = Cvalue.V.inject swept Ival.zero in
  let input, clob = initial in
  let input = Cvalue.Model.add_binding ~exact:true input
      (Locations.of_base untouched) ptr in
  let result = Lookup.find stack (input, clob) in
  assert (result.hit = None && result.rejected = [1, `Sweep]);
  Format.printf "exit holder escaping; matching input with a new holder rejected@."

let () =
  Observation.on_result observe;
  match Sys.getenv_opt "EVA_TEST_COLLECTOR_EFFECTS" with
  | Some "sweep" -> Boot.Main.extend sweep_check
  | Some "logger" ->
    Log.add_listener ~plugin:"eva" ~kind:[Log.Warning] ignore
  | _ -> ()
