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
  List.iter (Format.printf "| %s@.") (List.sort_uniq String.compare lines)

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
    Format.printf "value of x before %a: %a@." pretty_stmt last
      pretty_value Results.(before last);
    List.iter (fun callstack ->
        Format.printf "value of x before %a in %a: %a@." pretty_stmt last
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
    Format.printf "| end of main: gp = %a@."
      Cvalue.V_Or_Uninitialized.pretty v

let observe () =
  Format.printf "hits on body: %d@."
    (Eva.Statistics.get Eva.Statistics.cache_hits (kf "body"));
  Format.printf "reachability of body unknown: %b@."
    (Eva__Reach_delivery.reach_unknown_of (kf "body"));
  if env "VALUES" = Some "on" then values ();
  holder ();
  summary ()

(* ----- Modes ------------------------------------------------------------- *)

(* Caching disabled: neither memexec nor supplied entries. *)
let reference () =
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  observe ()

(* A first analysis, from the entry point of the command line, stores the
   entry of body, if any. Changing the entry point to main then resets the
   analysis. With NORESULTS=on, the states of body are not saved in the
   first analysis. *)
let produce_and_reset () =
  let no_results = env "NORESULTS" = Some "on" in
  if no_results then Eva.Parameters.NoResultsFunction.add
      (Kernel_function.get_definition (kf "body"));
  Eva.Analysis.compute ();
  let produced =
    match Producer.entries (kf "body") with
    | [ produced ] -> produced
    | _ -> assert false
  in
  Kernel.MainFunction.set "main";
  assert (not (Eva.Analysis.is_computed ()));
  if no_results then Eva.Parameters.NoResultsFunction.clear ();
  produced

(* Prints the Reach part of the entry of body, one write per line, sorted. *)
let print_part produced =
  match Entry.reach (Producer.cache_entry produced) with
  | None -> Format.printf "Reach part of the entry: unknown@."
  | Some part ->
    let lines = List.map (one_line Reach.pretty_write) part in
    List.iter (Format.printf "part: %s@.") (List.sort compare lines)

(* The entry of body is supplied to a second analysis, from main. With
   PART=drop, the entry is supplied by hand without its Reach part. *)
let replay () =
  let produced = produce_and_reset () in
  print_part produced;
  if env "PART" = Some "drop" then begin
    let entry = Producer.cache_entry produced in
    let exit = List.map (fun (k, (s, _)) -> k, s) (Entry.exit entry) in
    ignore
      (Supplied.supply ~safety:(Entry.safety entry) (kf "body")
         ~key:(Entry.key entry) ~input:(fst (Entry.input entry))
         ~footprint:(Entry.footprint entry) ~exit)
  end
  else ignore (Supplied.supply_produced produced);
  Format.printf "second analysis@.";
  Eva.Analysis.compute ();
  observe ()

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
