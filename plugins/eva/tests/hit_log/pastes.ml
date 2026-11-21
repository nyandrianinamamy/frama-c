(* Makes twice the request without callstack before P in child, after an
   analysis with -eva-hit-log. Each request served by the rule prints the
   number of its pastes, with option -eva-msg-key debug:hit-log. *)

open Eva

let main () =
  let hits = ref 0 in
  Cvalue_callbacks.register_call_results_hook
    (fun _callstack kf _state results ->
       match results with
       | `Reuse _ when Kernel_function.get_name kf = "parent" -> incr hits
       | _ -> ());
  Analysis.compute ();
  Format.printf "Hits of parent: %d.@." !hits;
  let child = Globals.Functions.find_by_name "child" in
  let p = !(Kernel_function.find_label child "P") in
  let h = Base.of_varinfo (Globals.Vars.find_from_astinfo "h" Global) in
  let request title =
    Format.printf "%s:@." title;
    let state = Results.(before p |> get_cvalue_model) in
    let only_h = Cvalue.Model.filter_base (Base.equal h) state in
    Format.printf "  @[%a@]@." Cvalue.Model.pretty only_h;
    state
  in
  let first = request "First request before P in child, without callstack" in
  let second = request "Repeated request" in
  Format.printf "The two answers are equal: %b.@."
    (Cvalue.Model.equal first second)

let () = Boot.Main.extend main
