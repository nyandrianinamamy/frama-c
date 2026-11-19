(* Test module of cache-safety.t: delivers the Safety part of an entry at a
   hit, then prints the statuses, the red contexts and the values at the end
   of main. Summary lines start with "| " and are sorted, so that run.t can
   compare two runs. *)

open Cil_types

module Supplied = Eva.Supplied_entries
module Producer = Eva.Cache_producer
module Entry = Eva.Cache_entry.Cvalue
module Results = Eva.Results

let kf = Globals.Functions.find_by_name

let global name = Globals.Vars.find_from_astinfo name Global

let formal f name =
  List.find (fun vi -> vi.vname = name) (Kernel_function.get_formals (kf f))

(* ----- Summary of an analysis -------------------------------------------- *)

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

(* An alarm by its name, other properties by their short form. *)
let pretty_property fmt ip =
  match ip with
  | Property.IPCodeAnnot { ica_ca; _ } when Alarms.find ica_ca <> None ->
    let alarm = Option.get (Alarms.find ica_ca) in
    Format.fprintf fmt "alarm %s" (Alarms.get_name alarm)
  | _ -> Property.short_pretty fmt ip

(* Every property with a status, at its location. *)
let statuses () =
  let line ip =
    Format.asprintf "%a: status of %a: %a" Fileloc.pretty
      (Property.location ip) pretty_property ip
      pretty_status (Property_status.get ip)
  in
  let lines = ref [] in
  Property_status.iter (fun ip ->
      match Property_status.get ip with
      | Never_tried -> ()
      | Best _ | Inconsistent _ -> lines := line ip :: !lines);
  !lines

let pretty_kinstr fmt = function
  | Kglobal -> Format.pp_print_string fmt "global"
  | Kstmt stmt -> Fileloc.pretty fmt (Cil_datatype.Stmt.loc stmt)

(* A callstack with its call sites, latest call first. *)
let pretty_callstack fmt = function
  | None -> Format.pp_print_string fmt "no callstack"
  | Some (callstack : Eva.Callstack.t) ->
    let pretty_call fmt (kf, stmt) =
      Format.fprintf fmt "%a :: %a <- " Kernel_function.pretty kf
        Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
    in
    List.iter (pretty_call fmt) callstack.stack;
    Kernel_function.pretty fmt callstack.entry_point

(* Every red context, with its callstack. *)
let red_contexts () =
  let target = function
    | Eva__Red_statuses.Alarm alarm -> "alarm " ^ Alarms.get_name alarm
    | Prop ip -> Format.asprintf "%a" pretty_property ip
  in
  let add kinstr t callstacks lines =
    let line callstack =
      Format.asprintf "%a: red context of %s in %a" pretty_kinstr kinstr
        (target t) pretty_callstack callstack
    in
    List.map line callstacks @ lines
  in
  Eva__Red_statuses.fold_contexts add []

(* The value of [name] at the end of the entry point. *)
let value name =
  let main = fst (Globals.entry_point ()) in
  let request = Results.at_end_of main in
  let main = Kernel_function.get_name main in
  match Results.(eval_var (global name) request |> as_integer) with
  | Ok n -> Format.asprintf "end of %s: %s = %a" main name Z.pp_print n
  | Error e ->
    Format.asprintf "end of %s: %s: %a" main name Results.pretty_error e

let summary names =
  let lines = statuses () @ red_contexts () @ List.map value names in
  List.iter (Format.printf "| %s@.") (List.sort_uniq String.compare lines)

let hits name =
  Format.printf "hits on %s: %d@." name
    (Eva.Statistics.get Eva.Statistics.cache_hits (kf name))

(* ----- Modes ------------------------------------------------------------- *)

(* Caching disabled: neither memexec nor supplied entries. Prints the
   Safety part of each analysed call of [observed]. *)
let reference ?observed names () =
  Option.iter (fun name ->
      Eva.Safety_part.on_result (fun callstack safety ->
          if Kernel_function.equal (Eva.Callstack.top_kf callstack) (kf name)
          then
            Format.printf "Safety part of %a: %a@." pretty_callstack
              (Some callstack) Eva.Safety_part.pretty safety))
    observed;
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  summary names

(* A first analysis from [producer] stores the entry of [body], whose
   Safety part is printed. Changing the entry point to [main] then resets the
   analysis with its alarms and statuses. *)
let produce_and_reset main =
  Eva.Analysis.compute ();
  let produced =
    match Producer.entries (kf "body") with
    | [produced] -> produced
    | _ -> assert false
  in
  let safety = Entry.safety (Producer.cache_entry produced) in
  let one_line write =
    let buffer = Buffer.create 80 in
    let fmt = Format.formatter_of_buffer buffer in
    Format.pp_set_margin fmt 1000;
    Format.fprintf fmt "%a@?" Eva.Safety_part.pretty_write write;
    Buffer.contents buffer
  in
  List.iter (fun w -> Format.printf "safety: %s@." (one_line w)) safety;
  Kernel.MainFunction.set main;
  assert (not (Eva.Analysis.is_computed ()));
  Format.printf "after the reset: %d statuses, %d red contexts@."
    (List.length (statuses ())) (List.length (red_contexts ()));
  produced

(* The entry of [body] is supplied to a second analysis, from the function
   named by EVA_TEST_CACHE_SAFETY_MAIN, main by default. *)
let replay () =
  let main =
    Option.value ~default:"main" (Sys.getenv_opt "EVA_TEST_CACHE_SAFETY_MAIN")
  in
  let produced = produce_and_reset main in
  ignore (Supplied.supply_produced produced);
  Eva.Analysis.compute ();
  hits "body";
  summary ["r1"; "r2"]

(* The last call of [body] in [caller]. *)
let call_of_body caller =
  let calls = Kernel_function.find_syntactic_callsites (kf "body") in
  let in_caller (k, _) = Kernel_function.equal k (kf caller) in
  match List.rev (List.sort compare (List.filter in_caller calls)) with
  | (_, stmt) :: _ -> stmt
  | [] -> assert false

(* The Safety part of the entry of [body] is delivered outside any analysis:
   twice for the call of [body] at line 26 of main, then its red contexts,
   with the call of [body] in [outer] as frame, for a callstack of
   [outer]. *)
let deliver () =
  let produced = produce_and_reset "main" in
  let safety = Entry.safety (Producer.cache_entry produced) in
  let thread = Eva.Thread.main_id in
  let at_hit =
    Eva.Callstack.init ~thread ~entry_point:(kf "main")
    |> Eva.Callstack.push (kf "body") (call_of_body "main")
  in
  let tables () = List.sort compare (statuses () @ red_contexts ()) in
  Eva__Safety_delivery.deliver at_hit safety;
  let once = tables () in
  Eva__Safety_delivery.deliver at_hit safety;
  Format.printf "a second delivery changes nothing: %b@." (once = tables ());
  let with_frame : Eva.Safety_part.write -> _ = function
    | Red_context r ->
      Some (Eva.Safety_part.Red_context
              { r with frames = [kf "body", call_of_body "outer"] })
    | Emitted_alarm _ | Emitted_status _ -> None
  in
  let from_outer = Eva.Callstack.init ~thread ~entry_point:(kf "outer") in
  Eva__Safety_delivery.deliver from_outer (List.filter_map with_frame safety);
  summary []

let bases vis =
  List.fold_left
    (fun acc vi -> Base.Hptset.add (Base.of_varinfo vi) acc)
    Base.Hptset.empty vis

let state bindings =
  let bind acc (vi, n) =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    let v = Cvalue.V.inject_int (Z.of_int n) in
    let v = Cvalue.V_Or_Uninitialized.initialized v in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size acc
  in
  List.fold_left bind Cvalue.Model.empty_map bindings

(* A hand-written entry of [pre] for x = 1. The requires clause belongs to
   the call site: the entry neither reads g nor carries a status. *)
let precondition () =
  let x = formal "pre" "x" and out = global "out" in
  let written = bases [out] in
  ignore
    (Supplied.supply (kf "pre")
       ~key:(bases [x])
       ~input:(state [x, 1])
       ~footprint:Supplied.{ read = bases [x]; written;
                             written_exit = written; written_sure = written }
       ~exit:[Supplied.empty_key, state [x, 1; out, 2]]);
  Eva.Analysis.compute ();
  hits "pre";
  summary ["out"]

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_SAFETY" with
  | Some "replay" -> Boot.Main.extend replay
  | Some "deliver" -> Boot.Main.extend deliver
  | Some "reference" -> Boot.Main.extend (reference ["r1"; "r2"])
  | Some "precondition" -> Boot.Main.extend precondition
  | Some "precondition-reference" ->
    Boot.Main.extend (reference ~observed:"pre" ["out"])
  | _ -> ()
