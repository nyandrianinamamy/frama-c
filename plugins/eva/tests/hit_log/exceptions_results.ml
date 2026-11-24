(* Analyses exceptions_results.c with -eva-hit-log, with an exception of its
   own raised in the hook run on the results of the second call of f that is
   a hit or that is analysed by a specification. Prints the answer to the
   state request at the start of f and before P, on each callstack of f seen
   by the hook and without callstack, and before Q in other. *)

open Eva

exception Injected

let callstacks = ref []
let count = ref 0

let () =
  Cvalue_callbacks.register_call_results_hook
    (fun callstack kf _state results ->
       if Kernel_function.get_name kf = "f" then begin
         callstacks := callstack :: !callstacks;
         let stop kind =
           incr count;
           Format.printf "Call of f: %s.@." kind;
           if !count = 2 then raise Injected
         in
         match results with
         | `Body _ -> Format.printf "Call of f: body analysed.@."
         | `Reuse _ | `Renamed_reuse _ | `Swept_reuse _ -> stop "hit"
         | `Spec _ -> stop "specification"
         | `Builtin _ -> ()
       end)

let answer request =
  match Results.get_cvalue_model_result request with
  | Ok Cvalue.Model.Top | Error Results.(Top | DisabledDomain) -> "unavailable"
  | Ok _ -> "value"
  | Error Bottom -> "unreachable"

let main () =
  begin
    try Analysis.compute ()
    with Injected -> Format.printf "The exception is caught.@."
  end;
  let f = Globals.Functions.find_by_name "f" in
  let other = Globals.Functions.find_by_name "other" in
  let before kf label = Results.before !(Kernel_function.find_label kf label) in
  let print title select =
    Format.printf "%s: start of f: %s, before P: %s@." title
      (answer (select (Results.at_start_of f))) (answer (select (before f "P")))
  in
  List.iteri
    (fun i callstack ->
       print (Format.asprintf "Call %d of f" (i + 1))
         (Results.in_callstack callstack))
    (List.rev !callstacks);
  print "Without callstack" Fun.id;
  Format.printf "Before Q in other: %s@." (answer (before other "Q"))

let () = Boot.Main.extend main
