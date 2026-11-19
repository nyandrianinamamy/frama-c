(* Four requests of the server on parts.c: the dead code of copy and of
   narrow, whose two branches are reached, and the statements that read and
   that write b at the first call to copy, which Studia, loaded after the
   analysis, computes with Inout.

   The server registers a client of the hooks on the changes of annotations
   when it loads, which emits a signal to the client of the server.
   This client is audited, and the lookup admits the supplied entries while
   it is registered. EVA_TEST_CACHE_PARTS_SERVER selects the results:
   "fresh" runs an analysis with caching disabled, "hits" runs it, supplies
   the entries it produced for the callees of parts.c and runs the analysis
   again, and "loaded" asks the results of the session given with -load. *)

open Cil_types

let kf = Globals.Functions.find_by_name
let global name = Globals.Vars.find_from_astinfo name Global

let first_call_to_copy () =
  Kernel_function.find_syntactic_callsites (kf "copy")
  |> List.map snd |> List.sort Cil_datatype.Stmt.compare |> List.hd

let requests () =
  Format.printf "statement results complete: %b@."
    (Eva.Results.statement_results_complete ());
  Dynamic.load_plugin "studia";
  let size = function `List l -> string_of_int (List.length l) | _ -> "?" in
  let ask name arg =
    match Server.Main.find name with
    | None -> Format.printf "%s: missing@." name
    | Some (_, handler) ->
      match handler arg with
      | `Assoc fields ->
        let field (k, v) = k ^ " " ^ size v in
        Format.printf "%s: %s@." name
          (String.concat ", " (List.map field fields))
      | _ -> Format.printf "%s: answered@." name
      | exception Log.AbortError _ -> Format.printf "%s: refused@." name
  in
  let dead_code f =
    let decl = Server.Printer_tag.SFunction (kf f) in
    Format.printf "%s: " f;
    ask "plugins.eva.ast.getDeadCode" (Server.Kernel_ast.Decl.to_json decl)
  in
  dead_code "copy";
  dead_code "narrow";
  let b = Var (global "b"), NoOffset in
  let call = Kstmt (first_call_to_copy ()) in
  let marker = Server.Printer_tag.PLval (Some (kf "deps_main"), call, b) in
  ask "plugins.studia.studia.getReadsLval"
    (Server.Kernel_ast.Marker.to_json marker);
  ask "plugins.studia.studia.getWritesLval"
    (Server.Kernel_ast.Marker.to_json marker)

let clear () =
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ()

let caching_disabled () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ()

let fresh () =
  caching_disabled ();
  requests ()

(* Studia, which [requests] loads, reads the states saved at the statements:
   it is loaded after the analysis with hits only. *)
let hits () =
  caching_disabled ();
  let callees = [ "copy"; "narrow"; "narrow_and_write"; "checked" ] in
  List.concat_map (fun f -> Eva.Cache_producer.entries (kf f)) callees
  |> List.iter (fun p -> ignore (Eva.Supplied_entries.supply_produced p));
  clear ();
  Eva.Parameters.Memexec.on ();
  Eva.Analysis.compute ();
  let hits f = Eva.Statistics.get Eva.Statistics.cache_hits (kf f) in
  Format.printf "hits: copy %d, narrow %d@." (hits "copy") (hits "narrow");
  requests ()

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_PARTS_SERVER" with
  | Some "fresh" -> Boot.Main.extend fresh
  | Some "hits" -> Boot.Main.extend hits
  | Some "loaded" -> Boot.Main.extend requests
  | _ -> ()
