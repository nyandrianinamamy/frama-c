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

let observe_refusals stack (r : Access.t) =
  let name = Kernel_function.get_name (Eva.Callstack.top_kf stack) in
  (match name with
   | "copy" ->
     assert (names r.reads = ["p"]);
     assert (names r.writes = ["q"]);
     let allocated = function Base.Allocated _ -> true | _ -> false in
     assert (Base.SetLattice.exists allocated r.designated)
   | "annotation" ->
     assert (List.mem Access.Statuses r.recorded)
   | "swept" ->
     assert (List.mem Access.Holders r.recorded)
   | "nested" ->
     assert (List.mem Access.Callers r.recorded)
   | _ -> ());
  Format.printf "%s %s@." name (first_reason r)

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
  | name -> failwith ("unexpected body: " ^ name)

let () =
  let observe stack result =
    match Sys.getenv_opt "EVA_TEST_BODY_ACCESS" with
    | Some "refusals" -> observe_refusals stack result
    | Some "restricted" ->
      assert (List.mem Access.Side_table result.refusals);
      Format.printf "restricted cvalue refused@."
    | Some "unknown" ->
      assert (first_reason result = "side-table");
      Format.printf "unclassified callback refused@."
    | _ -> observe_blocks stack result
  in
  Access.on_result observe;
  if Sys.getenv_opt "EVA_TEST_BODY_ACCESS" = Some "unknown" then
    Eva.Cvalue_callbacks.register_call_hook (fun _ _ _ _ -> ())
