open Cil_types

module Producer = Eva.Cache_producer
module Entry = Eva.Cache_entry.Cvalue
module Results = Eva.Results

let names bases =
  let name b = Format.asprintf "%a" Base.pretty b in
  Base.Hptset.fold (fun b names -> name b :: names) bases []
  |> List.sort String.compare

let kf = Globals.Functions.find_by_name
let global name = Globals.Vars.find_from_astinfo name Global
let leaf () = kf "leaf"

let check_value model vi n =
  let request = Results.in_cvalue_state model in
  let value = Results.eval_var vi request |> Results.as_integer in
  assert (value = Ok (Z.of_int n))

let inspect produced =
  let entry = Producer.cache_entry produced in
  let footprint = Entry.footprint entry in
  let ret = Option.get (Eva.Supplied_entries.return_variable (leaf ())) in
  let reads = ["__retres"; "p"; "q"] in
  let writes = ["\\result<leaf>"; "__retres"; "out"] in
  assert (names (Entry.key entry) = reads);
  assert (names footprint.read = reads);
  assert (names footprint.written = writes);
  assert (names footprint.written_exit = writes);
  assert (names footprint.written_sure = writes);
  assert (List.mem Eva.Body_access.States (Producer.recorded produced));
  assert (Option.is_some (Producer.inner produced));
  begin match Producer.used_functions produced with
    | [used, `Body] -> assert (Kernel_function.equal used (leaf ()))
    | _ -> assert false
  end;
  let input = fst (Entry.input entry) in
  check_value input (global "p") 3;
  check_value input (global "q") 4;
  begin match Entry.exit entry with
    | [_, (exit, _)] ->
      check_value exit (global "out") 7;
      check_value exit ret 2;
      let keep = Base.of_varinfo (global "keep") in
      assert (try ignore (Cvalue.Model.find_base keep exit); false
              with Not_found -> true)
    | _ -> assert false
  end;
  Format.printf
    "leaf: key __retres,p,q; writes out and both return blocks; used leaf (body)@."

let final_main_state () =
  Results.before (Kernel_function.find_return (kf "main"))
  |> Results.get_cvalue_model

let replay () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  let fresh = final_main_state () in
  let stored =
    match Producer.entries (leaf ()) with
    | [first; _] -> first
    | _ -> assert false
  in
  ignore (Eva.Supplied_entries.supply_produced stored);
  Project.clear ~selection:(State_selection.with_dependencies Eva.Analysis.self)
    ();
  Eva.Parameters.Memexec.on ();
  Eva.Analysis.compute ();
  assert (Eva.Statistics.get Eva.Statistics.cache_hits (leaf ()) = 2);
  assert (Eva.Statistics.get Eva.Statistics.memexec_hits (leaf ()) = 0);
  assert (Producer.entries (leaf ()) = []);
  let reused = final_main_state () in
  assert (Cvalue.Model.equal fresh reused);
  check_value reused (global "answer") 2;
  check_value reused (global "keep") 42;
  check_value reused (global "out") 7;
  Format.printf "same full caller state after replay: answer=2 keep=42 out=7@."

let partial () =
  let entry =
    match Producer.entries (kf "partial") with
    | [entry] -> Producer.cache_entry entry
    | _ -> assert false
  in
  let footprint = Entry.footprint entry in
  assert (names (Entry.key entry) = ["pair"]);
  assert (names footprint.read = []);
  assert (names footprint.written_exit = ["pair"]);
  assert (names footprint.written_sure = []);
  Format.printf "partial: pair is in the key and is not a sure write@."

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_PRODUCER" with
  | Some "replay" -> Boot.Main.extend replay
  | Some "partial" -> Boot.Main.extend partial
  | _ -> Boot.Main.extend (fun () ->
      assert (Eva.Statistics.get Eva.Statistics.memexec_hits (leaf ()) = 1);
      assert (Eva.Statistics.get Eva.Statistics.cache_hits (leaf ()) = 0);
      assert (Producer.entries (kf "main") = []);
      match Producer.entries (leaf ()) with
      | [entry] -> inspect entry
      | _ -> assert false)
