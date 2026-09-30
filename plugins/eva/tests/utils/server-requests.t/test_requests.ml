(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* Tests Eva requests by:
   - running the Eva analysis on C files from this directory;
   - sending Eva requests and printing the response. *)

module Self = Plugin.Register
    (struct
      let name = "Eva Requests Test"
      let shortname = "test"
      let help = "Plug-in for testing Eva requests"
    end)

module Target =
  Self.String
    (struct
      let option_name = "-test"
      let help = "Choose the requests to test"
      let default = ""
      let arg_name = "analysis|stats|call|dead_code|\
                      values|values_by_stmt|values_by_callstack|states"
    end)

(* ----- Building json of AST elements -------------------------------------- *)

module Printer_tag = Server.Printer_tag
module Kernel_ast = Server.Kernel_ast

let kf_json name =
  let kf = Globals.Functions.find_by_name name in
  Kernel_ast.Decl.to_json (Printer_tag.SFunction kf)

let lval_json kf stmt lval =
  let marker = Printer_tag.PLval (Some kf, Kstmt stmt, lval) in
  Kernel_ast.Marker.to_json marker

let expr_json kf stmt expr =
  let marker = Printer_tag.PExp (Some kf, Kstmt stmt, expr) in
  Kernel_ast.Marker.to_json marker

let stmt_json kf stmt =
  let marker = Printer_tag.PStmt (kf, stmt) in
  Kernel_ast.Marker.to_json marker

let parse_expr kf stmt str =
  let term_lval = Logic_parse_string.term kf str in
  let expr = Logic_to_c.term_to_exp term_lval in
  expr_json kf stmt expr

let parse_lval kf stmt str =
  let term_lval = Logic_parse_string.term_lval kf str in
  let lval = Logic_to_c.term_lval_to_lval term_lval in
  lval_json kf stmt lval

let parse_code_annot kf stmt str =
  let code_annot = Logic_parse_string.code_annot kf stmt str in
  let property = Property.ip_of_code_annot_single kf stmt code_annot in
  let marker = Printer_tag.PIP property in
  Kernel_ast.Marker.to_json marker

let find_local_var kf name =
  let is_x vi = vi.Cil_types.vorig_name = name in
  List.find is_x (Kernel_function.get_locals kf)

(* ----- Pretty prints json by replacing ids of markers. -------------------- *)

let replace_markers =
  let regexp = Str.regexp {|code:#[A-Za-z][0-9]+|} in
  let to_string pp = Format.asprintf "%a" pp in
  let subst str =
    let id = Str.matched_string str in
    try Kernel_ast.Marker.find id |> to_string Printer_tag.pp_localizable
    with Not_found ->
    try Kernel_ast.Decl.find id |> to_string Printer_tag.pp_declaration
    with Not_found -> id
  in
  Str.global_substitute regexp subst

let replace_newlines = String.map (function '\n' -> ' ' | c -> c)

let pp_string fmt s =
  replace_markers s |> replace_newlines |> Format.pp_print_string fmt

let rec pp_json fmt = function
  | `Null -> Format.pp_print_string fmt "null"
  | `Bool b -> Format.pp_print_bool fmt b
  | `Int a -> Format.pp_print_int fmt a
  | `Float f -> Format.fprintf fmt "%.3g" f
  | `String s -> pp_string fmt s
  | `List list ->
    Pretty_utils.pp_list ~pre:"@[<hv 2>[ " ~sep:",@ " ~suf:" ]@]" ~empty:"[]"
      pp_json fmt list
  | `Assoc list ->
    let pp_entry fmt (key, v) =
      Format.fprintf fmt "%a: %a" pp_string key pp_json v
    in
    Pretty_utils.pp_list ~pre:"@[<hv 2>{ " ~sep:",@ " ~suf:" }@]" ~empty:"{}"
      pp_entry fmt list

let pretty_json fmt = function
  | `Null -> ()
  | json -> Format.fprintf fmt " %a" pp_json json

(* ----- Send request and print the result. --------------------------------- *)

let pp_kind = Server.Main.pp_kind

let print_response kind request ~data ~response =
  if response = `Null then
    Self.feedback "Request %a %s%a;"
      pp_kind kind request pretty_json data
  else
    Self.feedback "@[<v>Request %a %s%a:@; %a@]"
      pp_kind kind request pretty_json data pretty_json response

(* Sends [request] with [data] argument, and prints the json response.
   If provided, applies [process_response] to the response before printing. *)
let send' ?(process_response=Fun.id) request data =
  match Server.Main.find request with
  | None -> Self.abort "Unknown request %s" request
  | Some (kind, handler) ->
    try
      let response = handler data |> process_response in
      print_response kind request ~data ~response;
      response
    with Server.Data.InputError msg ->
      Self.warning "@[<v>Request %a %s%a:@;  Error %s@]"
        pp_kind kind request pretty_json data msg;
      `Null

let send ?process_response request data =
  ignore (send' ?process_response request data)

(* Prints the 10 first elements of the array. *)
let fetch_array plugin array_name =
  let fetch = plugin ^ ".fetch" ^ array_name in
  let reload = plugin ^ ".reload" ^ array_name in
  let process_response json =
    match json with
    | `Assoc list -> List.assoc "updated" list
    | _ -> Self.abort "Invalid response to %s" fetch
  in
  send reload `Null;
  send ~process_response fetch (`Int 10)

(* ----- Printing values from the "getValues" request ----------------------- *)

let print_values json =
  send "plugins.eva.values.getValues" (`Assoc [ "target", json ])

let print_var_values kf stmt vi =
  let var_json = lval_json kf stmt (Cil.var vi) in
  print_values var_json

let print_lval_values kf stmt str =
  let lval_json = parse_lval kf stmt str in
  print_values lval_json

let print_expr_values kf stmt str =
  let expr_json = parse_expr kf stmt str in
  print_values expr_json

let print_code_annot_values kf stmt str =
  let code_annot_json = parse_code_annot kf stmt str in
  print_values code_annot_json

(* ----- Test various sequences of requests. ------------------------------- *)

let set_file filename =
  send "kernel.ast.setFiles" (`List [`String filename])

let test_analysis_requests () =
  set_file "stats.i";
  send "plugins.eva.analysis.getComputationState" `Null;
  send "plugins.eva.analysis.compute" `Null;
  send "plugins.eva.analysis.getComputationState" `Null;
  send "plugins.eva.analysis.clear" `Null;
  send "plugins.eva.analysis.getComputationState" `Null

let test_stats_requests () =
  set_file "stats.i";
  send "kernel.parameters.setEvaVerbose" (`Int 1);
  send "plugins.eva.analysis.compute" `Null;
  send "plugins.eva.stats.getProgramStats" `Null;
  fetch_array "plugins.eva.stats" "FunctionStats"

let test_dead_code_requests () =
  set_file "stats.i";
  send "plugins.eva.analysis.compute" `Null;
  send "plugins.eva.ast.getDeadCode" (kf_json "reachable");
  send "plugins.eva.ast.getDeadCode" (kf_json "unreachable");
  send "plugins.eva.ast.getDeadCode" (kf_json "coverage")

let test_call_requests () =
  set_file "callers.i";
  send "plugins.eva.analysis.compute" `Null;
  send "plugins.eva.ast.getCallers" (kf_json "main");
  send "plugins.eva.ast.getCallers" (kf_json "one_caller");
  send "plugins.eva.ast.getCallers" (kf_json "multiple_callers");
  send "plugins.eva.ast.getCallers" (kf_json "unreachable")

(* All tests below are applied on the "values.i" file. *)

(* Prints various values returned by the [getValues] request
   at the return statement of the "values" function. *)
let test_values_requests () =
  set_file "values.i";
  send "plugins.eva.analysis.compute" `Null;
  let kf = Globals.Functions.find_by_name "values" in
  let stmt = Kernel_function.find_return kf in
  let fundec = Kernel_function.get_definition kf in
  let top_locals = fundec.sbody.blocals in
  List.iter (print_var_values kf stmt) top_locals;
  print_lval_values kf stmt "a[5]";
  print_lval_values kf stmt "b[5]";
  print_lval_values kf stmt "nondet";
  print_lval_values kf stmt "st.array";
  print_expr_values kf stmt "42";
  print_expr_values kf stmt "one+a[5]";
  print_expr_values kf stmt "one+b[5]";
  print_expr_values kf stmt "one+nondet";
  print_code_annot_values kf stmt "assert valid: \\initialized(&one);";
  print_code_annot_values kf stmt "assert invalid: \\initialized(&uninit);";
  print_code_annot_values kf stmt "assert unknown: \\initialized(ptr);"

(* Prints the values returned by the [getValues] request
   for local variable [x] at each statement of function "values_by_stmt".
   Also tests the [getProbeInfo] request. *)
let test_values_by_stmt_requests () =
  set_file "values.i";
  send "plugins.eva.analysis.compute" `Null;
  let kf = Globals.Functions.find_by_name "values_by_stmt" in
  let x = find_local_var kf "x" in
  let print_values_at stmt =
    Self.feedback " ----- At statement %a ----- " Printer.pp_stmt stmt;
    send "plugins.eva.values.getProbeInfo" (stmt_json kf stmt);
    print_var_values kf stmt x
  in
  let fundec = Kernel_function.get_definition kf in
  List.iter print_values_at fundec.sallstmts

(* Prints the values returned by the [getValues] request
   for local variable [x] for each callstack of function "values_by_callstack".
   Also tests requests about callstacks. *)
let test_values_by_callstack_requests () =
  set_file "values.i";
  send "plugins.eva.analysis.compute" `Null;
  let kf = Globals.Functions.find_by_name "values_by_callstack" in
  let stmt = Kernel_function.find_return kf in
  let x = find_local_var kf "x" in
  let x_json = lval_json kf stmt (Cil.var x) in
  let list_json = `List [ x_json ] in
  let cs_json = send' "plugins.eva.callstack.getMarkersCallstacks" list_json in
  let eval_in_callstack callstack =
    send "plugins.eva.callstack.getCallstackInfo" callstack;
    let json = `Assoc [ "target", x_json ; "callstack", callstack ] in
    send "plugins.eva.values.getValues" json
  in
  List.iter eval_in_callstack (Json.list cs_json)

(* Test the [getStates] request on "states.i" file:
   - print filtered cvalue state at each statement of "main";
   - print complete cvalue state at the return statement of "main". *)
let test_states_requests () =
  set_file "states.i";
  send "plugins.eva.analysis.compute" `Null;
  let kf = Globals.Functions.find_by_name "main" in
  let print_values_at stmt =
    Self.feedback " ----- State at statement %a ----- " Printer.pp_stmt stmt;
    let json = `List [stmt_json kf stmt; `Bool true] in
    send "plugins.eva.analysis.getStates" json
  in
  let fundec = Kernel_function.get_definition kf in
  List.iter print_values_at fundec.sallstmts;
  Self.feedback " ----- Complete state at return statement ----- ";
  let stmt = Kernel_function.find_return kf in
  let json = `List [stmt_json kf stmt; `Bool false] in
  send "plugins.eva.analysis.getStates" json

(* ----- Run the tests. ----------------------------------------------------- *)

let run () =
  match Target.get () with
  | "analysis" -> test_analysis_requests ()
  | "stats" -> test_stats_requests ()
  | "call" -> test_call_requests ()
  | "dead_code" -> test_dead_code_requests ()
  | "values" -> test_values_requests ()
  | "values_by_stmt" -> test_values_by_stmt_requests ()
  | "values_by_callstack" -> test_values_by_callstack_requests ()
  | "states" -> test_states_requests ()
  | s -> Self.abort "Invalid argument %s for parameter %s." s Target.name

let () = Boot.Main.extend run
