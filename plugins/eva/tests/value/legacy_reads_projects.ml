(* Requests of Eva.Results over two projects, with the reads of the legacy
   result store that Eva.Legacy_read_trap reports for each of them. *)

open Eva

(* The requests made by the passes that Eva runs after the iteration of an
   analysis, and the reads outside any request, are counted apart. *)
let print_reported title =
  let some list = if list = [] then "none" else "some" in
  let passes, requests =
    List.partition (fun r -> Option.is_some r.Legacy_read_trap.pass)
      (Legacy_read_trap.requests ())
  in
  let reads = List.concat_map (fun r -> r.Legacy_read_trap.reads) passes in
  Format.printf "@[<v 2>%s:" title;
  if requests = [] then Format.printf "@ no request reported";
  List.iter (Format.printf "@ %a" Legacy_read_trap.pretty_request) requests;
  Format.printf "@ requests of the passes after the iteration: %s, \
                 with reads: %s" (some passes) (some reads);
  Format.printf "@ reads outside any request: %s"
    (some (Legacy_read_trap.stray_reads ()));
  Format.printf "@ reads ignored: %s@]@."
    (if Legacy_read_trap.ignored_reads () > 0 then "some" else "none")

let initial_state () = ignore Results.(at_start |> get_cvalue_model)

(* A copy of the current project in which Eva has no result. *)
let copy name =
  let project = Project.create_by_copy ~last:false name in
  let selection = State_selection.with_dependencies Analysis.self in
  Project.on project (fun () -> Project.clear ~selection ()) ();
  project

(* Runs [f] at the end of the iteration of the next analysis only. *)
let at_end_of_next_iteration =
  let hook = ref None in
  Analysis.register_computation_hook ~on:Computed
    (fun _ ->
       match !hook with
       | None -> ()
       | Some f -> hook := None; f ());
  fun f -> hook := Some f

let main () =
  Analysis.compute ();
  let first = Project.current () in
  (* A request in the first project, which has results, made at the end of
     the iteration of the second one: reported with its read. The passes of
     the second project are reported as well. *)
  let second = copy "second" in
  Legacy_read_trap.start ();
  at_end_of_next_iteration (Project.on first initial_state);
  Project.on second Analysis.compute ();
  print_reported
    "Request in the first project during the analysis of the second";
  (* An analysis of the third project started within a request of the first
     one, with a request of its own at the end of its iteration: the request
     of the first project has its own reads only; the request of the third
     project, made after its iteration, is a request of its own, as are the
     requests of its passes. *)
  let third = copy "third" in
  let f = Globals.Functions.find_by_name "f" in
  let stmt = Kernel_function.find_first_stmt f in
  let analyze_third _callstack =
    if not (Project.on third Analysis.is_computed ()) then begin
      at_end_of_next_iteration initial_state;
      Project.on third Analysis.compute ()
    end;
    true
  in
  Legacy_read_trap.start ();
  ignore Results.(before stmt |> filter_callstack analyze_third |> callstacks);
  print_reported "Request of the first project that starts an analysis";
  (* A request in the third project made within a request of the first one:
     two requests. *)
  let in_third _callstack = Project.on third initial_state (); true in
  Legacy_read_trap.start ();
  ignore Results.(before stmt |> filter_callstack in_third |> callstacks);
  print_reported "Request of the first project that makes one in the third";
  (* The report restarted within a request: this request started before, and
     is left out of the new report with its reads. The next request is the
     first one of the report. Without saved cvalue results, the filter is not
     applied and the report is not restarted: both requests are reported. *)
  let restart _callstack = Legacy_read_trap.start (); true in
  Legacy_read_trap.start ();
  ignore Results.(before stmt |> filter_callstack restart |> callstacks);
  initial_state ();
  print_reported "Report restarted within a request, then a request";
  Legacy_read_trap.stop ()

let () = Boot.Main.extend main
