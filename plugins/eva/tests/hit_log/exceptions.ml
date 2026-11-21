(* Analyses exceptions.c with -eva-hit-log four times: with an exception of
   its own raised in a hook run before the iteration, in a hook run at the
   call of leaf, in a hook run at the end of the analysis of the body of leaf,
   then without exception. After each analysis, and in the hook run when an
   analysis is aborted, prints the answer to the state request at each
   labelled statement and at the start of each function, and whether the
   requests are answered by the rule. *)

open Eva

exception Injected

type stage = Before_iteration | At_call | At_end_of_call | Nowhere

let stage = ref Nowhere

let name = function
  | Before_iteration -> "in a hook run before the iteration"
  | At_call -> "in a hook run at the call of leaf"
  | At_end_of_call -> "in a hook run at the end of the analysis of leaf"
  | Nowhere -> "nowhere"

let raise_at s = if !stage = s then raise Injected

let is_leaf kf = Kernel_function.get_name kf = "leaf"

let () =
  Cvalue_callbacks.register_at_start_hook
    (fun () -> raise_at Before_iteration);
  Cvalue_callbacks.register_call_hook
    (fun _callstack kf _state _kind -> if is_leaf kf then raise_at At_call);
  Cvalue_callbacks.register_call_results_hook
    (fun _callstack kf _state results ->
       match results with
       | `Body _ when is_leaf kf -> raise_at At_end_of_call
       | _ -> ())

let answer result =
  match result with
  | Ok Cvalue.Model.Top | Error Results.(Top | DisabledDomain) -> "unavailable"
  | Ok _ -> "value"
  | Error Bottom -> "unreachable"

let print_answers title =
  Format.printf "@[<v 2>%s:" title;
  Format.printf "@ requests answered by the rule: %b" (Eva__Hit_log.serving ());
  if Analysis.is_computed () then
    List.iter
      (fun (name, labels) ->
         let kf = Globals.Functions.find_by_name name in
         Format.printf "@ start of %s: %s" name
           Results.(answer (at_start_of kf |> get_cvalue_model_result));
         List.iter
           (fun label ->
              let stmt = !(Kernel_function.find_label kf label) in
              Format.printf "@ before %s in %s: %s" label name
                Results.(answer (before stmt |> get_cvalue_model_result)))
           labels)
      [ "main", [ "M" ]; "f", [ "A"; "B"; "C" ]; "leaf", [ "L" ] ]
  else Format.printf "@ Eva has no result";
  Format.printf "@]@."

let () =
  Analysis.register_computation_hook ~on:Aborted
    (fun _ -> print_answers "In the hook run when the analysis is aborted")

let clear () =
  Project.clear ~selection:(State_selection.with_dependencies Analysis.self) ()

let main () =
  List.iter
    (fun s ->
       clear ();
       stage := s;
       Format.printf "Exception %s.@." (name s);
       begin
         try Analysis.compute ()
         with Injected -> Format.printf "The exception is caught.@."
       end;
       print_answers "After the analysis")
    [ Before_iteration; At_call; At_end_of_call; Nowhere ]

let () = Boot.Main.extend main
