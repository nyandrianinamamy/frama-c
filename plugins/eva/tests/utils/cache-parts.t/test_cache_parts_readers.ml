(* Requests of Scope, Impact and Security slicing on parts.c, through their
   interfaces: no option of these plug-ins runs them on a program without
   annotations of their own. Each reads the results of Eva at statements
   and the graphs of Pdg, which it loads. The requests are made on the
   results of the session given with -load, about b before the last call
   to copy in deps_main: the requests of Scope go backwards from it, through
   the two other calls. *)

open Cil_types

let kf = Globals.Functions.find_by_name

let refused name f =
  match f () with
  | _ -> Format.printf "%s: computed@." name
  | exception Log.AbortError event ->
    Format.printf "%s: refused by %s@." name event.Log.evt_plugin

let requests () =
  Format.printf "statement results complete: %b@."
    (Eva.Results.statement_results_complete ());
  let deps_main = kf "deps_main" in
  let call =
    Kernel_function.find_syntactic_callsites (kf "copy")
    |> List.map snd |> List.sort Cil_datatype.Stmt.compare |> List.rev
    |> List.hd
  in
  let b = Var (Globals.Vars.find_from_astinfo "b" Global), NoOffset in
  refused "Scope.Datascope.get_data_scope_at_stmt"
    (fun () -> ignore (Scope.Datascope.get_data_scope_at_stmt deps_main call b));
  refused "Scope.Defs.get_defs"
    (fun () -> ignore (Scope.Defs.get_defs deps_main call b));
  refused "Scope.Zones.build_zones"
    (fun () -> ignore (Scope.Zones.build_zones deps_main call b));
  refused "Impact.Register.from_stmt"
    (fun () -> ignore (Impact.Register.from_stmt call));
  refused "Security_slicing.Components.get_direct_component"
    (fun () ->
       ignore (Security_slicing.Components.get_direct_component call))

let () = Boot.Main.extend requests
