(* Registers a hook run when Eva has results, which makes a request before P
   in f through a filter that reads the joined state of the legacy store. *)

open Eva

let () =
  Analysis.register_computation_hook ~on:Computed
    (fun _ ->
       let f = Globals.Functions.find_by_name "f" in
       let stmt = !(Kernel_function.find_label f "P") in
       let read _callstack =
         ignore (Eva__Cvalue_results.get_state (Before stmt));
         true
       in
       ignore Results.(before stmt |> filter_callstack read |> callstacks))
