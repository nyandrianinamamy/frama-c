(* Requests of Eva.Results over two projects, with the reads of the legacy
   result store that Eva.Legacy_read_trap reports for each of them. *)

open Eva

let print_reported title =
  let requests = Legacy_read_trap.requests () in
  Format.printf "@[<v 2>%s:" title;
  if requests = [] then Format.printf "@ no request reported";
  List.iter (Format.printf "@ %a" Legacy_read_trap.pretty_request) requests;
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
  (* A request in the first project, which has results, made while the second
     one is analysed: reported with its read. *)
  let second = copy "second" in
  Legacy_read_trap.start ();
  at_end_of_next_iteration (Project.on first initial_state);
  Project.on second Analysis.compute ();
  print_reported
    "Request in the first project during the analysis of the second";
  (* An analysis of the third project started within a request of the first
     one, with a request of its own at the end of its iteration: the request
     of the first project has its own reads only, those of the third project
     are ignored. *)
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
  Legacy_read_trap.stop ()

let () = Boot.Main.extend main
