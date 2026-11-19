module Access = Eva.Body_access
module Producer = Eva.Cache_producer
module Entry = Eva.Cache_entry.Cvalue
module Supply = Eva.Supplied_entries

let kf = Globals.Functions.find_by_name
let kf_name = Kernel_function.get_name
let same a b = Kernel_function.equal a (kf b)

let names = function
  | Base.SetLattice.Top -> failwith "unexpected Top"
  | Base.SetLattice.Set bases ->
    let add_name b names = (Base.to_varinfo b).vname :: names in
    Base.Hptset.fold add_name bases [] |> List.sort String.compare

let injected bases = names (Base.SetLattice.inject bases)

let member name = function
  | Base.SetLattice.Top -> false
  | Base.SetLattice.Set bases ->
    let var = Globals.Vars.find_from_astinfo name Global in
    Base.Hptset.mem (Base.of_varinfo var) bases

let mode = Sys.getenv_opt "EVA_TEST_NESTED_ACCESS"
let supplied_child = ref None
let outer_observations = ref 0
let supply_hint_at_marker = ref false
let enclosing_hint_stamps = ref 0

let check_child_reference stack (r : Access.t) =
  let stmt, entry =
    match r.children with
    | [[stmt], reference] -> stmt, Option.get (Entry.of_reference reference)
    | _ -> assert false
  in
  let fundec = Kernel_function.get_definition (Eva.Callstack.top_kf stack) in
  assert (List.exists (Cil_datatype.Stmt.equal stmt) fundec.sallstmts);
  assert (match Entry.statement entry with Body f -> same f "child");
  assert (injected (Entry.key entry) = ["payload"; "x"]);
  match !supplied_child with
  | None ->
    assert (List.exists
              (fun e -> entry == Producer.cache_entry e)
              (Producer.entries (kf "child")))
  | Some supplied -> assert (entry == supplied)

let split_mode = function
  | Some ("split-fresh" | "split-supplied" | "split-same") -> true
  | _ -> false

let observe stack (r : Access.t) =
  match kf_name (Eva.Callstack.top_kf stack) with
  | "outer" when mode <> Some "recursive" ->
    incr outer_observations;
    assert (r.refusals = []);
    assert (names r.reads = ["payload"; "x"]);
    assert (names r.dependencies = ["payload"]);
    assert (names r.writes = ["out"; "x"]);
    assert (names r.exit_writes = ["out"; "x"]);
    assert (injected r.sure_writes = ["out"; "x"]);
    assert (r.designated = Base.SetLattice.empty);
    assert (List.mem Access.Callers r.recorded);
    assert (List.mem Access.Guards r.recorded);
    check_child_reference stack r;
    Format.printf "outer: reads payload,x; depends on payload; writes out,x; \
                   recorded guards and child reference@."
  | "release" | "free_parent" as name ->
    let reason = Access.refusal_id (List.hd r.refusals) in
    assert (reason = "deallocation");
    Format.printf "%s refused %s@." name reason
  | "spec_parent" ->
    assert (r.refusals = []);
    assert (names r.reads = ["destination"; "selector"; "source"]);
    assert (names r.dependencies = ["destination"; "selector"; "source"]);
    assert (names r.writes = ["destination"]);
    assert (names r.exit_writes = ["destination"]);
    assert (Base.Hptset.is_empty r.sure_writes);
    assert (List.mem Access.Statuses r.recorded);
    assert (List.exists (fun (f, mode) -> same f "contract" && mode = `Spec)
              r.used_functions);
    assert (r.children = []);
    Format.printf "spec_parent: reads destination,selector,source; \
                   may write destination; recorded statuses inline@."
  | "maybe_overwrite" ->
    assert (member "x" r.reads && member "x" r.dependencies);
    Format.printf "maybe_overwrite: x is still an entry dependency@."
  | "inline_parent" ->
    assert (r.refusals = []);
    assert (Producer.entries (kf "requires_middle") = []);
    begin match r.children with
      | [[first; second], reference] ->
        assert (same (Kernel_function.find_englobing_kf first) "inline_parent");
        let middle = Kernel_function.find_englobing_kf second in
        assert (same middle "requires_middle");
        let entry = Option.get (Entry.of_reference reference) in
        assert (match Entry.statement entry with Body f -> same f "child");
        assert (List.exists
                  (fun e -> entry == Producer.cache_entry e)
                  (Producer.entries (kf "child")))
      | _ -> assert false
    end;
    Format.printf "inline_parent: retained child at the two-statement \
                   call path@."
  | "prefix_parent" ->
    assert (member "prefix_input" r.reads);
    assert (member "prefix_input" r.dependencies);
    assert (names r.writes = ["prefix_out"]);
    assert (r.exit_writes = Base.SetLattice.empty);
    assert (Base.Hptset.is_empty r.sure_writes);
    Format.printf "prefix_parent: prefix_input and prefix_out are covered \
                   even without an exit@."
  | "formal_parent" ->
    assert (r.refusals = []);
    assert (names r.reads = ["formal_in"; "formal_out"; "local"]);
    assert (names r.dependencies = ["formal_in"; "formal_out"]);
    assert (names r.writes = ["formal_out"; "local"]);
    assert (names r.exit_writes = ["formal_out"]);
    assert (Base.Hptset.is_empty r.sure_writes);
    Format.printf "formal_parent: local is in the prefix footprint; \
                   formal_in supplies its value@."
  | "sweep_parent" ->
    assert (Eva__Body_access.verdict r = Error Access.Sweep);
    assert (Base.Hptset.is_empty r.sweeps);
    Format.printf "sweep_parent: child's lexical sweep is foreign@."
  | "hint_parent" ->
    let generation = Access.hint_generation_number
        (Option.get r.hint_generation) in
    assert (generation = 0);
    incr enclosing_hint_stamps;
    Format.printf "hint_parent: hint generation %d@." generation
  | "hint_marker" when !supply_hint_at_marker ->
    let entry = List.hd (Producer.entries (kf "hint_reader")) in
    ignore (Supply.supply_produced entry)
  | "f" when split_mode mode ->
    assert (member "x" r.dependencies && member "y" r.dependencies);
    assert (member "x" r.exit_writes && member "y" r.exit_writes);
    assert (injected r.sure_writes = ["out"]);
    Format.printf "f: x,y are possible writes and entry dependencies; \
                   only out is sure@."
  | ("f" | "inactive_parent") when mode = Some "history" ->
    assert (Eva__Body_access.verdict r = Error Access.Side_table);
    Format.printf "allocation clause: side-table before storage@."
  | "f" when mode = Some "dump" ->
    assert (r.reads = Base.SetLattice.top);
    assert (r.dependencies = Base.SetLattice.top);
    assert (Eva__Body_access.verdict r = Error Access.Dump);
    Format.printf "dump: Top reads and dependencies before storage@."
  | _ -> ()

let only_outer () =
  match Producer.entries (kf "outer") with
  | [produced] ->
    let entry = Producer.cache_entry produced in
    assert (injected (Entry.key entry) = ["payload"]);
    assert (injected (Entry.footprint entry).read = ["payload"; "x"]);
    Format.printf "stored outer key: payload@.";
    produced
  | _ -> assert false

let prepare_next_run () =
  Project.clear ~selection:(State_selection.with_dependencies Eva.Analysis.self)
    ();
  Eva.Parameters.Memexec.on ()

let replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let outer = only_outer () in
  let child = kf "child" in
  let first, matching =
    match Producer.entries child with
    | [first; matching] -> first, matching
    | _ -> assert false
  in
  begin match mode with
    | Some "replay" ->
      ignore (Supply.supply_produced first);
      supplied_child := Some (Supply.supply_produced matching)
    | Some ("automatic" | "recursive") ->
      ignore (Supply.supply_produced outer);
      Kernel.MainFunction.set
        (if mode = Some "automatic" then "automatic_main" else "recursive_main")
    | _ -> assert false
  end;
  prepare_next_run ();
  Eva.Analysis.compute ();
  match mode with
  | Some "replay" ->
    assert (!outer_observations = 2);
    assert (Eva.Statistics.get Eva.Statistics.cache_hits child = 2);
    assert (Producer.entries child = []);
    ignore (only_outer ());
    Format.printf "confirmed two child hits, one after a rejected candidate@."
  | Some ("automatic" | "recursive") ->
    assert (Eva.Statistics.get Eva.Statistics.cache_hits (kf "outer") = 0)
  | _ -> assert false

let first_entry name =
  match Producer.entries (kf name) with
  | entry :: _ -> entry
  | [] -> failwith ("no produced entry for " ^ name)

let supply name = ignore (Supply.supply_produced (first_entry name))

let start_consumer ?main () =
  Option.iter Kernel.MainFunction.set main;
  prepare_next_run ();
  Eva.Analysis.compute ()

let check_split_key () =
  let key = Entry.key (Producer.cache_entry (first_entry "f")) in
  assert (injected key = ["p"; "x"; "y"]);
  Format.printf "stored f key: p,x,y@."

let split_replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  check_split_key ();
  match mode with
  | Some "split-fresh" ->
    supply "f";
    start_consumer ~main:"second" ()
  | Some "split-supplied" ->
    supply "pick";
    start_consumer ();
    assert (Eva.Statistics.get Eva.Statistics.cache_hits (kf "pick") = 1);
    assert (Producer.entries (kf "pick") = []);
    check_split_key ();
    Format.printf "confirmed supplied pick hit before observing f@.";
    Supply.clear ();
    supply "f";
    start_consumer ~main:"second" ()
  | Some "split-same" ->
    supply "f";
    start_consumer ()
  | _ -> assert false

let status_replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  supply "f";
  start_consumer ~main:"second" ();
  assert (Eva.Statistics.get Eva.Statistics.cache_hits (kf "f") = 0)

let delivery_replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let produced = first_entry "f" in
  let entry = Producer.cache_entry produced in
  Format.printf "f: %d child references@." (List.length (Entry.children entry));
  if mode = Some "delivery-hand" then begin
    let exit = List.map (fun (key, (state, _)) -> key, state)
        (Entry.exit entry) in
    ignore (Supply.supply ?reach:(Entry.reach entry) (kf "f")
              ~key:(Entry.key entry)
              ~input:(fst (Entry.input entry)) ~footprint:(Entry.footprint entry)
              ~exit)
  end else
    ignore (Supply.supply_produced produced);
  Format.printf "consumer analysis@.";
  start_consumer ()

let guard_replay () =
  let module Recorder = Eva__Body_access in
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let mid = Supply.supply_produced (first_entry "mid") in
  (* Exercise the winning-entry composition with the actual produced
     observation. Lookup below refuses mid until nested delivery exists. *)
  let f = kf "f" in
  let stack = Eva.Callstack.init ~thread:Eva.Thread.main_id ~entry_point:f in
  let stmt = Kernel_function.find_first_stmt f in
  let child_stack = Eva.Callstack.push (kf "mid") stmt stack in
  let _, observed = Recorder.capture stack (fun () ->
      Eva__Call_cache.include_supplied child_stack mid ~returns:true)
  in
  let observed = Option.get observed in
  assert (List.exists (fun (f, mode) -> same f "g" && mode = `Body)
            observed.used_functions);
  Format.printf "supplied mid observation contributes transitive g@.";
  start_consumer ();
  Supply.clear ();
  supply "f";
  start_consumer ~main:"second" ();
  assert (Eva.Statistics.get Eva.Statistics.cache_hits f = 0)

let inline_replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let entry = first_entry "spec_parent" in
  assert (Entry.children (Producer.cache_entry entry) = []);
  ignore (Supply.supply_produced entry);
  start_consumer ();
  assert (Eva.Statistics.get Eva.Statistics.cache_hits (kf "spec_parent") = 0)

let sweep_replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  assert (Producer.entries (kf "sweep_parent") = []);
  supply "own_sweep";
  start_consumer ();
  assert (Eva.Statistics.get Eva.Statistics.cache_hits (kf "own_sweep") = 1);
  assert (Producer.entries (kf "sweep_parent") = [])

let hint_replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  supply "hint_parent";
  supply_hint_at_marker := true;
  start_consumer ();
  assert (!enclosing_hint_stamps = 4);
  assert (Eva.Statistics.get Eva.Statistics.cache_hits (kf "hint_reader") = 1)

let () =
  Access.on_result ~audited:true observe;
  match mode with
  | Some ("replay" | "automatic" | "recursive") -> Boot.Main.extend replay
  | Some "fresh" -> Boot.Main.extend (fun () -> ignore (only_outer ()))
  | Some "status" -> Boot.Main.extend status_replay
  | Some ("delivery-hand" | "delivery-produced") ->
    Boot.Main.extend delivery_replay
  | Some "guard" -> Boot.Main.extend guard_replay
  | Some "inline" -> Boot.Main.extend inline_replay
  | Some "sweep" -> Boot.Main.extend sweep_replay
  | Some "hints" -> Boot.Main.extend hint_replay
  | mode when split_mode mode -> Boot.Main.extend split_replay
  | _ -> ()
