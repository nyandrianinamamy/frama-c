(* Parts of cache entries owned by From and Inout. A first analysis, with
   caching disabled, produces the entries of the callees of parts.c. They are
   supplied to a second analysis, in which the calls to these callees hit
   the entries. EVA_TEST_CACHE_PARTS selects what the two analyses
   compare. *)

open Cil_types

module Producer = Eva.Cache_producer
module Supplied = Eva.Supplied_entries
module Results = Eva.Results

let kf = Globals.Functions.find_by_name
let global name = Globals.Vars.find_from_astinfo name Global
let callees = [ "copy"; "narrow"; "narrow_and_write"; "checked" ]

let line stmt = Fileloc.line (Cil_datatype.Stmt.loc stmt)

(* The calls of [callee], in the order of the program. *)
let calls callee =
  Kernel_function.find_syntactic_callsites (kf callee)
  |> List.map snd |> List.sort Cil_datatype.Stmt.compare

let one_line pp x =
  let buffer = Buffer.create 80 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 1000;
  Format.fprintf fmt "%a@?" pp x;
  String.split_on_char '\n' (Buffer.contents buffer)
  |> List.map String.trim |> List.filter (( <> ) "") |> String.concat "; "

let clear () =
  Project.clear
    ~selection:(State_selection.with_dependencies Eva.Analysis.self) ()

let stat stat callee = Eva.Statistics.get stat (kf callee)
let hits callee = stat Eva.Statistics.cache_hits callee
let rejected reason callee = stat (Eva.Statistics.cache_rejected reason) callee

(* The first analysis, with caching disabled. Returns the entries produced
   for the callees, oldest first for each callee. *)
let first_analysis () =
  clear ();
  Eva.Parameters.Memexec.off ();
  Eva.Analysis.compute ();
  List.concat_map (fun f -> Producer.entries (kf f)) callees

(* The second analysis, with the entries of the first one supplied. *)
let second_analysis produced =
  List.iter (fun p -> ignore (Supplied.supply_produced p)) produced;
  clear ();
  Eva.Parameters.Memexec.on ();
  Eva.Analysis.compute ()

let part_names produced =
  Eva.Cache_part.names (Eva.Cache_entry.Cvalue.parts
                          (Producer.cache_entry produced))

let print_parts produced =
  List.iter
    (fun p ->
       let entry = Producer.cache_entry p in
       let Eva.Cache_entry.Body f = Eva.Cache_entry.Cvalue.statement entry in
       Format.printf "entry of %a: parts [%s]@." Kernel_function.pretty f
         (String.concat ", " (part_names p)))
    produced

(* ----- From --------------------------------------------------------------- *)

(* The whole table of callwise dependencies, by call site. *)
let callwise_froms () =
  let table = ref [] in
  From.Callwise.iter (fun ki deps -> table := (ki, deps) :: !table);
  List.sort (fun (k, _) (k', _) -> Cil_datatype.Kinstr.compare k k') !table

let same_froms fresh reused =
  List.length fresh = List.length reused
  && List.for_all2
    (fun (k, d) (k', d') ->
       Cil_datatype.Kinstr.equal k k' && Eva.Assigns.equal d d')
    fresh reused

let print_froms table callee =
  List.iter
    (fun stmt ->
       let deps = List.assoc (Kstmt stmt) table in
       Format.printf "%s at line %d: %s@." callee (line stmt)
         (one_line Eva.Assigns.pretty deps))
    (calls callee)

(* -calldeps is set: the dependencies of each call site after the second
   analysis, where the three calls to copy hit, are those of the first. *)
let from () =
  let produced = first_analysis () in
  print_parts produced;
  let fresh = callwise_froms () in
  second_analysis produced;
  Format.printf "hits: copy %d@." (hits "copy");
  let reused = callwise_froms () in
  Format.printf "callwise dependencies equal at %d call sites: %b@."
    (List.length fresh) (same_froms fresh reused);
  print_froms reused "copy";
  print_froms reused "deps_main"

(* -calldeps is set only after the first analysis: its entries have no From
   part. In the second analysis, every candidate is rejected and the bodies
   are analysed, which records their dependencies. *)
let missing () =
  let produced = first_analysis () in
  print_parts produced;
  Dynamic.Parameter.Bool.on "-calldeps" ();
  second_analysis produced;
  List.iter
    (fun f ->
       Format.printf "%s: hits %d, rejected for missing-part %d@." f (hits f)
         (rejected "missing-part" f))
    callees;
  print_froms (callwise_froms ()) "copy"

(* ----- Inout -------------------------------------------------------------- *)

let value_after stmt name =
  Results.(after stmt |> eval_var (global name) |> as_cvalue)
  |> one_line Cvalue.V.pretty

let callwise_inout callee =
  List.map
    (fun stmt -> Inout.get_precise_inout ~stmt (kf callee)) (calls callee)

(* The actuals after the calls to narrow and narrow_and_write, and the
   callwise inputs and outputs of these calls. *)
let observe () =
  let narrow = List.hd (calls "narrow")
  and write = List.hd (calls "narrow_and_write") in
  (value_after narrow "g", value_after write "h"),
  callwise_inout "narrow" @ callwise_inout "narrow_and_write"

let inout () =
  let produced = first_analysis () in
  print_parts produced;
  let (g, h), fresh = observe () in
  Format.printf "caching disabled: g after narrow %s, h after \
                 narrow_and_write %s@." g h;
  second_analysis produced;
  Format.printf "hits: narrow %d, narrow_and_write %d@."
    (hits "narrow") (hits "narrow_and_write");
  let (g', h'), reused = observe () in
  Format.printf "after the hits: g after narrow %s, h after \
                 narrow_and_write %s@." g' h';
  Format.printf "callwise inputs and outputs equal: %b@."
    (List.for_all2 Inout_type.equal fresh reused)

(* ----- Checks of the assigns clauses -------------------------------------- *)

(* The assigns and from clauses of the contract of checked. *)
let clauses () =
  let f = kf "checked" in
  Property.ip_of_spec f Kglobal ~active:[] (Annotations.funspec f)
  |> List.filter
    (function Property.IPAssigns _ | Property.IPFrom _ -> true | _ -> false)

let print_statuses moment =
  List.iter
    (fun ip ->
       Format.printf "%s: %a: %a@." moment Property.short_pretty ip
         Property_status.pretty (Property_status.get ip))
    (clauses ())

(* A change of a correctness parameter of Eva removes the statuses emitted by
   Eva. The parameter is then set back to its value. *)
let remove_eva_statuses () =
  let name = "-eva-warn-pointer-subtraction" in
  let value = Dynamic.Parameter.Bool.get name () in
  Dynamic.Parameter.Bool.set name (not value);
  Dynamic.Parameter.Bool.set name value

(* -from-verify-assigns is set: the clauses of checked are checked in the
   first analysis. Their statuses are removed, and both calls to checked hit
   in the second analysis: the clauses are checked again at the hits. *)
let verify () =
  let produced = first_analysis () in
  print_statuses "caching disabled";
  remove_eva_statuses ();
  print_statuses "statuses removed";
  second_analysis produced;
  Format.printf "hits: checked %d@." (hits "checked");
  print_statuses "after the hits"

(* ----- Readers of the states saved at statements -------------------------- *)

let readers () =
  let produced = first_analysis () in
  second_analysis produced;
  let sum f = List.fold_left (fun acc callee -> acc + f callee) 0 callees in
  Format.printf "hits %d, rejected for consumer %d@."
    (sum hits) (sum (rejected "consumer"))

(* ----- Values given in another project or for another callstack --------- *)

(* Three parts of this test, which no consumer needs. During each analysis of
   the body of copy, a value of each is given: for the callstack of the body
   in the current project, for the same callstack while another project is
   current, and for the callstack of the caller. Only the first one is kept
   with the entry. *)
let project () =
  let register name =
    Eva.Cache_part.register ~name ~needed:(fun () -> false)
      ~restore:(fun _ _ _ () -> ()) ()
  in
  let kept = register "kept"
  and other_project = register "other-project"
  and caller = register "caller" in
  let other = Project.create "other" in
  let give callstack f _state results =
    match results with
    | `Body _ when Kernel_function.equal f (kf "copy") ->
      Eva.Cache_part.provide kept callstack ();
      Project.on other (Eva.Cache_part.provide other_project callstack) ();
      Option.iter
        (fun outer -> Eva.Cache_part.provide caller outer ())
        (Eva.Callstack.pop callstack)
    | _ -> ()
  in
  Eva.Cvalue_callbacks.register_call_results_hook ~cache_protocol:true give;
  print_parts (first_analysis ())

let () =
  match Sys.getenv_opt "EVA_TEST_CACHE_PARTS" with
  | Some "from" -> Boot.Main.extend from
  | Some "missing" -> Boot.Main.extend missing
  | Some "inout" -> Boot.Main.extend inout
  | Some "verify" -> Boot.Main.extend verify
  | Some "readers" -> Boot.Main.extend readers
  | Some "project" -> Boot.Main.extend project
  | _ -> ()
