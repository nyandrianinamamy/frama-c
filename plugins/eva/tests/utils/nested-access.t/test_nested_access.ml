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
    Base.Hptset.fold (fun b names -> (Base.to_varinfo b).vname :: names) bases []
    |> List.sort String.compare

let injected bases = names (Base.SetLattice.inject bases)

let member name = function
  | Base.SetLattice.Top -> false
  | Base.SetLattice.Set bases ->
    Base.Hptset.mem (Base.of_varinfo (Globals.Vars.find_from_astinfo name Global))
      bases

let mode = Sys.getenv_opt "EVA_TEST_NESTED_ACCESS"
let supplied_child = ref None
let outer_observations = ref 0

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
        assert (same (Kernel_function.find_englobing_kf second) "requires_middle");
        let entry = Option.get (Entry.of_reference reference) in
        assert (match Entry.statement entry with Body f -> same f "child");
        assert (List.exists
                  (fun e -> entry == Producer.cache_entry e)
                  (Producer.entries (kf "child")))
      | _ -> assert false
    end;
    Format.printf "inline_parent: retained child at the two-statement call path@."
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

let () =
  Access.on_result observe;
  match mode with
  | Some ("replay" | "automatic" | "recursive") -> Boot.Main.extend replay
  | Some "fresh" -> Boot.Main.extend (fun () -> ignore (only_outer ()))
  | _ -> ()
