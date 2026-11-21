(* Requests of Eva.Results on legacy_reads.c, with the reads of the legacy
   result store that Eva.Legacy_read_trap reports for each of them. *)

open Eva

let kf name = Globals.Functions.find_by_name name
let label kf name = !(Kernel_function.find_label kf name)

let print_reported title =
  let requests = Legacy_read_trap.requests () in
  Format.printf "@[<v 2>%s:" title;
  if requests = [] then Format.printf "@ no request reported";
  List.iter (Format.printf "@ %a" Legacy_read_trap.pretty_request) requests;
  Format.printf "@]@."

let print_ignored title =
  Format.printf "@[<v 2>%s:@ requests reported: %d@ reads ignored: %s@]@."
    title (List.length (Legacy_read_trap.requests ()))
    (if Legacy_read_trap.ignored_reads () > 0 then "some" else "none")

let first_stmt () = Kernel_function.find_first_stmt (kf "f")

(* The instrument is on from the start, so that the requests made during the
   analysis are seen. *)
let () = Legacy_read_trap.start ()

(* During the iteration, Eva answers no request from the store. *)
let first_call = ref true
let () =
  Cvalue_callbacks.register_call_hook
    (fun _callstack kf _state _kind ->
       if !first_call && Kernel_function.get_name kf = "f" then begin
         first_call := false;
         let state = Results.(before (first_stmt ()) |> get_cvalue_model) in
         Format.printf "Request at the first call of f, answered by top: %b@."
           (Cvalue.Model.is_top state);
         print_ignored "During the iteration"
       end)

(* At the end of the iteration, Eva has results and answers from the store;
   the analysis still runs. *)
let () =
  Analysis.register_computation_hook
    (function
      | Computed | Aborted ->
        let call = label (kf "main") "C2" in
        ignore Results.(before call |> get_cvalue_model);
        print_ignored "At the end of the iteration"
      | NotComputed | Computing -> ())

let main () =
  begin
    try Analysis.compute ()
    with Log.AbortError _ -> Format.printf "The analysis has stopped.@."
  end;
  print_ignored "After the analysis, for the requests made during it";
  let main = kf "main" and f = kf "f" in
  let stmt = first_stmt () in
  let dead = label main "D" in
  let g = Globals.Vars.find_from_astinfo "g" Global in
  let root = Callstack.init ~thread:Thread.main_id ~entry_point:main in
  let callstack1 = Callstack.push f (label main "C1") root in
  let callstack2 = Callstack.push f (label main "C2") root in
  let state request () = ignore (Results.get_cvalue_model request) in
  let requests = Results.[
      "State before a statement, joined",
      state (before stmt);
      "State before a statement, in one callstack",
      state (before stmt |> in_callstack callstack1);
      "State after a statement, joined",
      state (after stmt);
      "State after a statement, in one callstack",
      state (after stmt |> in_callstack callstack2);
      "State at the start of a function, joined",
      state (at_start_of f);
      "State at the start of a function, in one callstack",
      state (at_start_of f |> in_callstack callstack1);
      "State at the end of a function, joined",
      state (at_end_of f);
      "State at the end of a function, in one callstack",
      state (at_end_of f |> in_callstack callstack2);
      "Initial state, joined",
      state at_start;
      "Initial state, in one callstack",
      state (at_start |> in_callstack root);
      "Final state, joined",
      state (at_end ());
      "Final state, in one callstack",
      state (at_end () |> in_callstack root);
      "State before a statement, in two callstacks",
      state (before stmt |> in_callstacks [ callstack1; callstack2 ]);
      "State before a statement, in the callstacks kept by a filter",
      state (before stmt |> filter_callstack (fun _ -> true));
      "Callstacks reaching a statement",
      (fun () -> ignore (before stmt |> callstacks));
      "State before an unreachable statement, joined",
      state (before dead);
      "Value of g before a statement, joined",
      (fun () ->
         let value = before stmt |> eval_var g |> as_cvalue in
         Format.printf "g: %a@." Cvalue.V.pretty value);
    ]
  in
  let report (title, request) =
    Legacy_read_trap.start ();
    request ();
    print_reported title
  in
  List.iter report requests;
  let is_if stmt = match stmt.Cil_types.skind with If _ -> true | _ -> false in
  let fundec = Kernel_function.get_definition main in
  let condition = List.find is_if fundec.sallstmts in
  Legacy_read_trap.start ();
  let positive, negative = Results.condition_truth_value condition in
  Format.printf "Truth values of the condition g > 5: %b, %b@."
    positive negative;
  print_reported "Truth values of a condition";
  Legacy_read_trap.stop ()

let () = Boot.Main.extend main
