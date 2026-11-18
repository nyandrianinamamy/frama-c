module Access = Eva.Body_access

let names = function
  | Base.SetLattice.Top -> failwith "unexpected Top"
  | Base.SetLattice.Set bases ->
    let add b names = (Base.to_varinfo b).vname :: names in
    List.sort String.compare (Base.Hptset.fold add bases [])

let first_reason (r : Access.t) =
  match r.refusals with
  | [] -> "would-store"
  | reason :: _ -> Access.refusal_id reason

let assert_writes (result : Access.t) ~may ~exit ~sure =
  assert (names result.writes = may);
  assert (names result.exit_writes = exit);
  assert (names (Base.SetLattice.inject result.sure_writes) = sure)

let observe_refusals stack (r : Access.t) =
  let name = Kernel_function.get_name (Eva.Callstack.top_kf stack) in
  (match name with
   | "copy" ->
     assert (names r.reads = ["p"]);
     assert (names r.writes = ["q"]);
     let allocated = function Base.Allocated _ -> true | _ -> false in
     assert (Base.SetLattice.exists allocated r.designated)
   | "precondition" ->
     assert (names r.reads = ["p"]);
     assert_writes r ~may:["q"] ~exit:["q"] ~sure:["q"];
     assert (r.refusals = [])
   | "contract" | "annotation" ->
     assert (names r.reads = ["x"]);
     assert (r.refusals = []);
     assert (List.mem Access.Statuses r.recorded)
   | "swept" ->
     assert (List.mem Access.Holders r.recorded)
   | "nested" ->
     assert (List.mem Access.Callers r.recorded)
   | _ -> ());
  Format.printf "%s %s@." name (first_reason r)

let observe_annotations stack (r : Access.t) =
  let name = Kernel_function.get_name (Eva.Callstack.top_kf stack) in
  let read expected =
    assert (names r.reads = expected);
    assert (r.refusals = []);
    assert (List.mem Access.Statuses r.recorded);
    Format.printf "%s reads %s@." name (String.concat ", " expected)
  in
  match name with
  | "selected" -> read ["post_only"; "selector"]
  | "select_behavior" | "use_allocated" -> ()
  | "read_assertion" -> read ["assertion_only"]
  | "read_invariant" ->
    assert (List.mem "invariant_only" (names r.reads));
    assert (r.refusals = []);
    assert (List.mem Access.Statuses r.recorded);
    Format.printf "read_invariant reads invariant_only@."
  | "read_pointer" -> read ["checked"]
  | "read_string" -> read ["message"; "text"]
  | "read_old" -> read ["before_only"; "post_input"]
  | "narrowing" ->
    assert_writes r ~may:["narrowed"] ~exit:["narrowed"] ~sure:[];
    read ["narrowed"]
  | "opaque_assertion" | "opaque_contract" ->
    assert (r.reads = Base.SetLattice.top);
    let reason = if name = "opaque_assertion" then Access.Annotation
      else Access.Contract
    in
    assert (r.refusals = [reason]);
    assert (List.mem Access.Statuses r.recorded);
    Format.printf "%s reads Top and refuses %s@." name (first_reason r)
  | "allocation_table" ->
    assert (names r.reads = []);
    assert (r.refusals = [Access.Side_table]);
    Format.printf "%s refuses side-table@." name
  | "valid_pointer" ->
    assert (names r.reads = ["allocated_ptr"]);
    let allocated = function Base.Allocated _ -> true | _ -> false in
    assert (Base.SetLattice.exists allocated r.designated);
    assert (r.refusals = [Access.Allocated_block]);
    Format.printf "valid_pointer designates an allocated block@."
  | "alarm_assertion" -> read ["divisor"]
  | name -> failwith ("unexpected body: " ^ name)

let observe_blocks stack (result : Access.t) =
  match Kernel_function.get_name (Eva.Callstack.top_kf stack) with
  | "main" ->
    assert (names result.reads = ["p"]);
    assert (names result.writes = ["q"]);
    assert (names result.exit_writes = ["q"]);
    assert (names (Base.SetLattice.inject result.sure_writes) = ["q"]);
    assert (names result.designated = ["x"]);
    assert (result.recorded = [Reached; States; Zones]);
    assert (result.refusals = []);
    Format.printf "reads p, writes q@."
  | "paths" ->
    assert (names result.writes = ["both"; "dead"; "pair"; "q"]);
    assert (names result.exit_writes = ["both"; "pair"; "q"]);
    assert (names (Base.SetLattice.inject result.sure_writes) = ["both"; "q"]);
    Format.printf
      "W = both, dead, pair, q; W_exit = both, pair, q; W_sure = both, q@."
  | "guard" ->
    assert (names result.reads = ["g"]);
    assert_writes result ~may:["g"; "out"] ~exit:["g"; "out"] ~sure:["out"];
    assert (List.mem Access.Guards result.recorded);
    assert (result.refusals = []);
    Format.printf "guard reduction contributes possible writes only@."
  | "locals" ->
    assert (names result.reads = ["x"]);
    assert_writes result ~may:["out"; "x"] ~exit:["out"; "x"] ~sure:["out"];
    assert (result.refusals = []);
    Format.printf "initialized local scope binding contributes a possible write@."
  | "correlated" ->
    assert (names result.reads = ["b"]);
    assert_writes result ~may:["b"; "dead"; "marker"]
      ~exit:["b"; "dead"; "marker"] ~sure:["marker"];
    Format.printf "exit graph retains dead across correlated guards@."
  | "alarm" ->
    assert (List.mem Access.Alarms result.recorded);
    assert (List.mem Access.Statuses result.recorded);
    assert (result.refusals = []);
    Format.printf "alarm and status joins recorded@."
  | "volatile_local" ->
    assert (names result.writes = ["vp"; "x"]);
    assert (names (Base.SetLattice.inject result.sure_writes) = ["vp"]);
    Format.printf "volatile local scope entry is a possible write only@."
  | "inactive" ->
    assert (not (List.mem Access.Statuses result.recorded));
    assert (names result.reads = ["g"]);
    assert (result.refusals = []);
    Format.printf "inactive behavior: requires status outside the body@."
  | "inactive_caller" -> ()
  | "temporary_mix" ->
    assert (first_reason result = "side-table");
    Format.printf "temporary origin history access refused@."
  | name -> failwith ("unexpected body: " ^ name)

let () =
  let observe stack result =
    match Sys.getenv_opt "EVA_TEST_BODY_ACCESS" with
    | Some "annotations" -> observe_annotations stack result
    | Some ("refusals" | "inout") -> observe_refusals stack result
    | Some "restricted" ->
      assert (List.mem Access.Side_table result.refusals);
      Format.printf "restricted cvalue refused@."
    | Some "unknown" ->
      assert (first_reason result = "side-table");
      Format.printf "unclassified callback refused@."
    | Some "hit" ->
      if Kernel_function.get_name (Eva.Callstack.top_kf stack) = "copy" then begin
        assert (names result.reads = ["p"]);
        assert_writes result ~may:["q"] ~exit:["q"] ~sure:["q"];
        Format.printf "copy %s@." (first_reason result)
      end
    | Some "interrupted" ->
      let name = Kernel_function.get_name (Eva.Callstack.top_kf stack) in
      assert (name = "leaf");
      assert (first_reason result = "would-store");
      Format.printf "completed body: %s@." name
    | _ -> observe_blocks stack result
  in
  Access.on_result observe;
  if Sys.getenv_opt "EVA_TEST_BODY_ACCESS" = Some "interrupted" then
    Eva.Analysis.register_computation_hook ~on:Aborted (fun _ ->
        assert (not (Eva__Body_access.is_recording ()));
        Eva.Statistics.export_as_csv
          ~filename:(Filepath.of_string "interrupted.tsv") ();
        Format.printf "interrupted body recorder unwound@.");
  if Sys.getenv_opt "EVA_TEST_BODY_ACCESS" = Some "unknown" then
    Eva.Cvalue_callbacks.register_call_hook (fun _ _ _ _ -> ())
