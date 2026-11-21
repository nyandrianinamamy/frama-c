(* Analyses a copy of the current project from a hook at the end of the call
   of main in the current one, then makes requests in both projects. *)

open Eva

let shown base =
  match Base.to_varinfo base with
  | vi -> not (Cil.is_in_libc vi.vattr)
  | exception Base.Not_a_C_variable -> false

let pretty_answer fmt = function
  | Ok Cvalue.Model.Top | Error (Results.Top | DisabledDomain) ->
    Format.pp_print_string fmt "unavailable"
  | Error Results.Bottom -> Format.pp_print_string fmt "unreachable"
  | Ok state -> Cvalue.Model.pretty fmt (Cvalue.Model.filter_base shown state)

let print_answer title request =
  Format.printf "  @[<v 2>%s:@ %a@]@." title pretty_answer
    (Results.get_cvalue_model_result request)

let print_requests name =
  let main = Globals.Functions.find_by_name "main" in
  let f = Globals.Functions.find_by_name "f" in
  let p = !(Kernel_function.find_label f "P") in
  Format.printf "Project %s:@." name;
  Legacy_read_trap.start ();
  print_answer "main, before its first statement"
    Results.(before (Kernel_function.find_first_stmt main));
  print_answer "f, before P, joined" (Results.before p);
  List.iter
    (fun callstack ->
       let title =
         Format.asprintf "f, before P, %a"
           Legacy_read_trap.pretty_callstack callstack
       in
       print_answer title Results.(before p |> in_callstack callstack))
    (Results.(before p |> callstacks) |> List.sort Callstack.compare_lex);
  Legacy_read_trap.stop ();
  let reported = Legacy_read_trap.requests () in
  let reads = List.concat_map (fun r -> r.Legacy_read_trap.reads) reported in
  Format.printf "  requests reported: %d; reads of the legacy store: %d@."
    (List.length reported) (List.length reads)

let main () =
  let other = Project.create_by_copy ~last:false "other" in
  let analysed = ref false in
  Cvalue_callbacks.register_call_results_hook
    (fun _callstack kf _state results ->
       match results with
       | `Body _ when not !analysed && Kernel_function.get_name kf = "main" ->
         analysed := true;
         Project.on other Analysis.compute ();
         Format.printf "The analysis of project other has ended in a hook of \
                        the analysis of project %s.@."
           (Project.get_name (Project.current ()))
       | _ -> ());
  Analysis.compute ();
  print_requests (Project.get_name (Project.current ()));
  Project.on other print_requests "other"

let () = Boot.Main.extend main
