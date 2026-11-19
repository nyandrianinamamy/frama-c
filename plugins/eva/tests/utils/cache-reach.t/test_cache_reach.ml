(* Test module of cache-reach.t: delivers the Reach part of an entry at a
   hit, then prints what the readers of the analysis see in the body: the
   statements reached and their callstacks, the dead code, the statuses, the
   guard outcomes, the call sites and the zones. Summary lines start with
   "| " and are sorted, so that run.t can compare two runs. *)

open Cil_types

module Supplied = Eva.Supplied_entries
module Producer = Eva.Cache_producer
module Entry = Eva.Cache_entry.Cvalue
module Results = Eva.Results
module Reach = Eva.Reach_part

let kf = Globals.Functions.find_by_name

let env name = Sys.getenv_opt ("EVA_TEST_CACHE_REACH_" ^ name)

let line stmt = Filepos.line (Fileloc.start_pos (Cil_datatype.Stmt.loc stmt))

let pretty_stmt fmt stmt =
  Format.fprintf fmt "stmt %d (line %d)" stmt.sid (line stmt)

(* A callstack with its call sites, latest call first. *)
let pretty_callstack fmt (callstack : Eva.Callstack.t) =
  let pretty_call fmt (kf, stmt) =
    Format.fprintf fmt "%a :: line %d <- " Kernel_function.pretty kf
      (line stmt)
  in
  List.iter (pretty_call fmt) callstack.stack;
  Kernel_function.pretty fmt callstack.entry_point

let pretty_callstacks fmt = function
  | [] -> Format.pp_print_string fmt "none"
  | callstacks ->
    let callstacks = List.sort Eva.Callstack.compare callstacks in
    Pretty_utils.pp_list ~sep:", " pretty_callstack fmt callstacks

(* [Format.asprintf] on one line: each line break, with the spaces around
   it, becomes one space. *)
let sprintf format =
  let one_line text =
    match String.split_on_char '\n' text with
    | [ _ ] | [] -> text
    | lines -> String.concat " " (List.map String.trim lines)
  in
  Format.kasprintf one_line format

let one_line pretty x = sprintf "%a" pretty x

let body_stmts () = (Kernel_function.get_definition (kf "body")).sallstmts

let in_body stmt =
  Kernel_function.equal (Kernel_function.find_englobing_kf stmt) (kf "body")

(* The prefix of the lines printed by the readers below: empty after the
   analysis, "restored " after an installation of saved results, and
   "original " in the original project after an installation in a copy. *)
let tag = ref ""

let printf format =
  Format.kasprintf (fun text -> Format.printf "%s%s%!" !tag text) format

(* ----- Readers ----------------------------------------------------------- *)

(* The callstacks in which a state is saved, or reached by a hit, before and
   after each statement of body. *)
let reached () =
  let line stmt =
    sprintf "reach: %a: before in %a; after in %a" pretty_stmt stmt
      pretty_callstacks Results.(before stmt |> callstacks)
      pretty_callstacks Results.(after stmt |> callstacks)
  in
  List.map line (body_stmts ())

(* The classification of the server request of dead code, from the same
   queries: unreachable without a state before, non-terminating with a state
   before and none after. *)
let dead_code () =
  let line stmt =
    let before = Results.(before stmt |> is_empty) in
    let after = Results.(after stmt |> is_empty) in
    let kind =
      if before then "unreachable"
      else if after then "non-terminating"
      else "reached"
    in
    sprintf "dead code: %a: %s" pretty_stmt stmt kind
  in
  List.map line (body_stmts ())

let pretty_status fmt = function
  | Property_status.Never_tried -> Format.pp_print_string fmt "never tried"
  | Inconsistent _ -> Format.pp_print_string fmt "inconsistent"
  | Best (status, _) ->
    Format.pp_print_string fmt
      (match status with
       | True -> "valid"
       | False_if_reachable -> "invalid"
       | False_and_reachable -> "invalid and reachable"
       | Dont_know -> "unknown")

(* Every property with a status, at its location. *)
let statuses () =
  let line ip =
    sprintf "%a: status of %a: %a" Fileloc.pretty
      (Property.location ip) Property.short_pretty ip
      pretty_status (Property_status.get ip)
  in
  let lines = ref [] in
  Property_status.iter (fun ip ->
      match Property_status.get ip with
      | Never_tried -> ()
      | Best _ | Inconsistent _ -> lines := line ip :: !lines);
  !lines

(* The guard outcomes of the conditions of body. *)
let guards () =
  let line stmt =
    match stmt.skind with
    | If _ ->
      let then_, else_ = Results.condition_truth_value stmt in
      Some (sprintf "guard: %a: then %b, else %b"
              pretty_stmt stmt then_ else_)
    | _ -> None
  in
  List.filter_map line (body_stmts ())

let callsites () =
  let calls (caller, stmts) =
    List.map (fun stmt ->
        sprintf "%a at line %d" Kernel_function.pretty caller
          (line stmt))
      stmts
  in
  let sites = List.concat_map calls (Results.callsites (kf "body")) in
  [ "call sites of body: " ^ String.concat ", " (List.sort compare sites) ]

(* The zones registered at the positions of body. *)
let zones () =
  let add (position : Eva.Position.t) access lines =
    match position with
    | Local (stmt, callstack) when in_body stmt ->
      let access : Eva__Inout_access.t = access in
      sprintf "zones: %a in %a: read %a; write %a" pretty_stmt stmt
        pretty_callstack callstack
        Memory_zone.pretty access.read Memory_zone.pretty access.write
      :: lines
    | _ -> lines
  in
  Eva__Inout_access.fold add []

let summary () =
  let lines =
    reached () @ dead_code () @ statuses () @ guards () @ callsites ()
    @ zones ()
  in
  List.iter (printf "| %s@.") (List.sort_uniq String.compare lines)

(* The value of x before the last statement of body, over all callstacks
   and in each one. A hit callstack answers top: its states are not
   recorded. *)
let values () =
  match List.rev (body_stmts ()) with
  | [] -> ()
  | _return :: last :: _ ->
    let x = List.hd (Kernel_function.get_formals (kf "body")) in
    let pretty_value fmt request =
      match Results.(eval_var x request |> as_cvalue_result) with
      | Ok v -> Cvalue.V.pretty fmt v
      | Error e -> Results.pretty_error fmt e
    in
    printf "value of x before %a: %a@." pretty_stmt last
      pretty_value Results.(before last);
    List.iter (fun callstack ->
        printf "value of x before %a in %a: %a@." pretty_stmt last
          pretty_callstack callstack pretty_value
          Results.(before last |> in_callstack callstack))
      (List.sort Eva.Callstack.compare Results.(before last |> callstacks))
  | [ _ ] -> ()

(* The value of gp at the end of main. *)
let holder () =
  match Globals.Vars.find_from_astinfo "gp" Global with
  | exception Not_found -> ()
  | gp ->
    let request = Results.at_end_of (kf "main") in
    let v = Results.(eval_var gp request |> as_cvalue_or_uninitialized) in
    printf "| end of main: gp = %a@." Cvalue.V_Or_Uninitialized.pretty v

(* The number of control points of body reached by hits, counted once per
   callstack, read from the delivery itself: under -eva-no-results, the
   queries answer no callstack. *)
let hit_points () =
  let count point = List.length (Eva__Reach_delivery.callstacks point) in
  let count_stmt n stmt =
    n + count (Eva__Domain_store.Before stmt)
    + count (Eva__Domain_store.After stmt)
  in
  printf "points of body reached by hits: %d@."
    (List.fold_left count_stmt 0 (body_stmts ()))

(* With EXPORT=on, the annotations that Export generates in body. They are
   removed after printing, so that Export can run again. *)
let export () =
  if env "EXPORT" = Some "on" then begin
    let fundec = Kernel_function.get_definition (kf "body") in
    ignore (Visitor.visitFramacFunction (Eva.Export.generator ()) fundec);
    let exported stmt ca =
      printf "exported before line %d: %a@." (line stmt)
        Printer.pp_code_annotation ca;
      Annotations.remove_code_annot Eva.Export.emitter stmt ca
    in
    List.iter (fun stmt ->
        List.iter (exported stmt)
          (Annotations.code_annot ~emitter:Eva.Export.emitter stmt))
      fundec.sallstmts
  end

let observe () =
  printf "hits on body: %d@."
    (Eva.Statistics.get Eva.Statistics.cache_hits (kf "body"));
  printf "reachability of body unknown: %b@."
    (Eva__Reach_delivery.reach_unknown_of (kf "body"));
  printf "visits of body skipped: %b@."
    (Eva__Safety_delivery.visits_skipped (kf "body"));
  hit_points ();
  if env "VALUES" = Some "on" then values ();
  export ();
  holder ();
  summary ()

(* ----- Saved results ----------------------------------------------------- *)

(* With RESTORE set, the results of the analysis are taken by
   [Eva_results.get_results] and installed by [Eva_results.set_results], in
   the current project (RESTORE=same) or in a copy of the project, from the
   results taken in the copy (RESTORE=copy). The readers run again on the
   installed results, their lines prefixed by "restored "; with REFINE=on,
   the refinement of the statuses of alarms runs first. After an
   installation in a copy, the readers run again in the original project,
   their lines prefixed by "original ". The results taken in a project
   cannot be installed in another one: they name its functions. *)
let restore () =
  let install results =
    Eva.Eva_results.set_results results;
    tag := "restored ";
    printf "results computed: %b@." (Eva.Analysis.is_computed ());
    if env "REFINE" = Some "on" then Eva__Eval_annots.mark_green_and_red ();
    observe ();
    tag := ""
  in
  match env "RESTORE" with
  | None -> ()
  | Some "same" -> install (Eva.Eva_results.get_results ())
  | Some "copy" ->
    let copy = Project.create_by_copy ~last:false "copy" in
    Project.on copy (fun () -> install (Eva.Eva_results.get_results ())) ();
    tag := "original ";
    observe ();
    tag := ""
  | Some mode -> failwith ("RESTORE=" ^ mode)

(* ----- Modes ------------------------------------------------------------- *)

(* [no_results setting on] sets, if [on], or clears the options under which
   an analysis saves no state: of body with "body"
   (-eva-no-results-function body), of every function with "global"
   (-eva-no-results). *)
let no_results setting on =
  match setting with
  | None -> ()
  | Some "body" ->
    if on then Eva.Parameters.NoResultsFunction.add
        (Kernel_function.get_definition (kf "body"))
    else Eva.Parameters.NoResultsFunction.clear ()
  | Some "global" -> Eva.Parameters.ResultsAll.set (not on)
  | Some setting -> failwith ("no results: " ^ setting)

(* Caching disabled: neither memexec nor supplied entries. *)
let reference () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  observe ();
  restore ()

(* A first analysis, from the entry point of the command line, stores the
   entry of body, if any. Changing the entry point to main then resets the
   analysis. With PRODUCER set, the first analysis saves no state of body
   (see [no_results]). *)
let produce_and_reset () =
  no_results (env "PRODUCER") true;
  Eva.Analysis.compute ();
  let produced =
    match Producer.entries (kf "body") with
    | [ produced ] -> produced
    | _ -> assert false
  in
  Kernel.MainFunction.set "main";
  assert (not (Eva.Analysis.is_computed ()));
  no_results (env "PRODUCER") false;
  produced

(* Prints the Reach part of the entry of body, one write per line, sorted,
   then whether its points are recorded. *)
let print_part produced =
  match Entry.reach (Producer.cache_entry produced) with
  | None -> Format.printf "Reach part of the entry: unknown@."
  | Some { joins; points } ->
    let writes = joins @ Option.value ~default:[] points in
    let lines = List.map (one_line Reach.pretty_write) writes in
    List.iter (Format.printf "part: %s@.") (List.sort compare lines);
    if points = None then Format.printf "points of the part: not recorded@."

(* The entry of body is supplied to a second analysis, from main. With
   PART=drop, the entry is supplied by hand without its Reach part; with
   PART=nopoints, with its Reach part without the points. With SECOND=on,
   the produced entry is supplied after the entry written by hand, as a
   second candidate. With CONSUMER set, the second analysis saves no state
   of body (see [no_results]). *)
let replay () =
  let produced = produce_and_reset () in
  print_part produced;
  let entry = Producer.cache_entry produced in
  let by_hand reach =
    let exit = List.map (fun (k, (s, _)) -> k, s) (Entry.exit entry) in
    ignore
      (Supplied.supply ~safety:(Entry.safety entry) ?reach (kf "body")
         ~key:(Entry.key entry) ~input:(fst (Entry.input entry))
         ~footprint:(Entry.footprint entry) ~exit);
    if env "SECOND" = Some "on" then ignore (Supplied.supply_produced produced)
  in
  begin match env "PART" with
    | Some "drop" -> by_hand None
    | Some "nopoints" ->
      let without_points (part : Reach.part) = { part with points = None } in
      by_hand (Option.map without_points (Entry.reach entry))
    | _ -> ignore (Supplied.supply_produced produced)
  end;
  no_results (env "CONSUMER") true;
  Format.printf "second analysis@.";
  Eva.Analysis.compute ();
  observe ();
  restore ()

(* After -load, without a new analysis. *)
let loaded () =
  assert (Eva.Analysis.is_computed ());
  observe ()

(* The entry of child is produced by an analysis from main, then supplied
   to an analysis from parent. The Reach part of parent is printed after
   each of its analyses. *)
let enclosing () =
  Reach.on_result (fun callstack part ->
      if Kernel_function.equal (Eva.Callstack.top_kf callstack) (kf "parent")
      then
        let lines = List.map (one_line Reach.pretty_write) part in
        List.iter (Format.printf "part of parent: %s@.")
          (List.sort compare lines));
  Eva.Analysis.compute ();
  let produced =
    match Producer.entries (kf "child") with
    | [ produced ] -> produced
    | _ -> assert false
  in
  Kernel.MainFunction.set "parent";
  assert (not (Eva.Analysis.is_computed ()));
  ignore (Supplied.supply_produced produced);
  Format.printf "second analysis@.";
  Eva.Analysis.compute ();
  Format.printf "hits on child: %d@."
    (Eva.Statistics.get Eva.Statistics.cache_hits (kf "child"))

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_REACH" with
  | Some "replay" -> Boot.Main.extend replay
  | Some "reference" -> Boot.Main.extend reference
  | Some "loaded" -> Boot.Main.extend loaded
  | Some "enclosing" -> Boot.Main.extend enclosing
  | _ -> ()
