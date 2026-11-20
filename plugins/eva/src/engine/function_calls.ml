(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types
open Eval

let save_results f =
  Parameters.ResultsAll.get () && not (Parameters.NoResultsFunction.mem f)

let info name : (module State_builder.Info_with_size) =
  (module struct
    let name = "Eva.Function_calls." ^ name
    let size = 17
    let dependencies = [ Self.state ]
  end)

module StmtSet = Cil_datatype.Stmt.Set
module Callers = Kernel_function.Map.Make (StmtSet)
module CallersTable = Kernel_function.Make_Table (Callers) (val info "Callers")

(* Reports a read of a legacy table to {!Legacy_read_guard}. *)
let notify access ~store kf what =
  Legacy_read_guard.notify access ~store (fun fmt ->
      Format.fprintf fmt "%s of %a" what Kernel_function.pretty kf)

(* Merges the call into the legacy table, which it reads. *)
let register_call call =
  let kf = Callstack.top_kf call.callstack in
  match Callstack.top_caller call.callstack with
  | None -> CallersTable.add kf Kernel_function.Map.empty
  | Some (callsite, caller) ->
    notify Getter ~store:"call-relations" kf "callers";
    let callsite = StmtSet.singleton callsite in
    let change calls =
      let prev_stmts = Kernel_function.Map.find_opt caller calls in
      let new_stmts =
        Option.fold ~none:callsite ~some:(StmtSet.union callsite) prev_stmts
      in
      Kernel_function.Map.add caller new_stmts calls
    in
    let add _kf = Kernel_function.Map.singleton caller callsite in
    ignore (CallersTable.memo ~change add kf)

let registered kf =
  notify Availability ~store:"call-relations" kf "registered call";
  CallersTable.mem kf

(* ----- Call relations ----------------------------------------------------- *)

(* The table of call relations is part of the legacy result store: a call
   below a memexec hit is not registered. The hit log answers the readers
   below from the callstacks of the invocations it records, when it
   describes the current results; it sets [recorded_relations], since it
   cannot be a dependency of this module. *)
type relations = StmtSet.t Kernel_function.Map.t Kernel_function.Map.t

let recorded_relations : (unit -> relations option) ref = ref (fun () -> None)
let set_recorded_relations f = recorded_relations := f

(* The relations of the hit log, or the legacy table, for the reader
   [label]. [point] prints what is read. *)
let relations ~label point =
  Legacy_read_guard.reader label @@ fun () ->
  match !recorded_relations () with
  | Some relations ->
    Legacy_read_guard.resolved point
      (fun fmt -> Format.pp_print_string fmt "call relations of the hit log");
    `Recorded relations
  | None ->
    Legacy_read_guard.notify Getter ~store:"call-relations" point;
    `Legacy

let callers_of kf ~label =
  let point fmt = Kernel_function.pretty fmt kf in
  match relations ~label point with
  | `Recorded relations -> Kernel_function.Map.find_opt kf relations
  | `Legacy -> CallersTable.find_opt kf

let is_called kf =
  Option.is_some (callers_of kf ~label:"Eva.Function_calls.is_called")

let callers kf =
  match callers_of kf ~label:"Eva.Function_calls.callers" with
  | Some calls -> List.map fst (Kernel_function.Map.bindings calls)
  | None -> []

let callsites kf =
  match callers_of kf ~label:"Eva.Function_calls.callsites" with
  | Some calls ->
    Kernel_function.Map.bindings calls
    |> List.map (fun (kf, set) -> kf, StmtSet.elements set)
  | None -> []

let count_callsites _kf callers count =
  Kernel_function.Map.fold
    (fun _caller callsites count -> count + StmtSet.cardinal callsites)
    callers count

let nb_callsites () =
  let point fmt = Format.pp_print_string fmt "all call sites" in
  match relations ~label:"Eva.Function_calls.nb_callsites" point with
  | `Recorded relations -> Kernel_function.Map.fold count_callsites relations 0
  | `Legacy -> CallersTable.fold count_callsites 0

type analysis_target =
  [ `Builtin of string * Builtins.builtin * funspec
  | `Spec of Cil_types.funspec
  | `Body of Cil_types.fundec * bool ]

type results = Complete | Partial | NoResults
type analysis_status =
    Unreachable | SpecUsed | Builtin of string | Analyzed of results

module Status = Datatype.Make (
  struct
    include Datatype.Serializable_undefined
    type t = analysis_status
    let name = "Function_calls.Status"
    let reprs = [ Unreachable ]
    let pretty fmt t =
      let str = match t with
        | Unreachable -> "Unreachable"
        | SpecUsed -> "Spec"
        | Builtin name -> "Builtin " ^ name
        | Analyzed _ -> "Analyzed"
      in
      Format.fprintf fmt "%s" str
  end)

module StatusTable = Kernel_function.Make_Table (Status) (val info "StatusTable")

(* All statuses bound to a given function should be identical, except for
   recursive functions that may not be completely unrolled: the body is first
   analyzed, and then the spec is used. This can also lead to partial and
   complete analyses of the same function, depending on the success of the
   unrolling for each call. *)
let merge_status s1 s2 =
  match s1, s2 with
  | Analyzed result, SpecUsed  | SpecUsed, Analyzed result ->
    Analyzed (if result = Complete then Partial else result)
  | Analyzed Partial, Analyzed Complete | Analyzed Complete, Analyzed Partial ->
    Analyzed Partial
  | _, _ ->
    assert (s1 = s2);
    s1

let status_of_target = function
  | `Builtin (name, _, _) -> Builtin name
  | `Spec _ -> SpecUsed
  | `Body (_, results) -> Analyzed (if results then Complete else NoResults)

(* Merges the status into the legacy table, which it reads. *)
let register_status kf status =
  notify Getter ~store:"analysis-status" kf "analysis status";
  let change prev_status = merge_status prev_status status in
  ignore (StatusTable.memo ~change (fun _ -> status) kf)

let analysis_status kf =
  notify Availability ~store:"analysis-status" kf "analysis status";
  try StatusTable.find kf
  with Not_found -> Unreachable


(* Must be consistent with the choice made by [analysis_target] below. *)
let use_spec_instead_of_definition ?(recursion_depth = -1) kf =
  Ast_info.start_with_frama_c_builtin (Kernel_function.get_name kf) ||
  Builtins.is_builtin_overridden kf ||
  recursion_depth >= Parameters.RecursiveUnroll.get () ||
  not (Kernel_function.is_definition kf) ||
  Kernel_function.Set.mem kf (Parameters.UseSpec.get ())

(* Returns the function specification of [kf], with generated assigns clauses
   if they are missing. *)
let get_funspec callsite kf =
  let loc =
    match callsite with
    | Kglobal -> None
    | Kstmt stmt -> Some (Cil_datatype.Stmt.loc stmt)
  in
  Populate_spec.populate_funspec ?loc ~do_body:true kf [`Assigns];
  Annotations.funspec kf

let analysis_target ?(recursion_depth = -1) kf callsite =
  match Builtins.find_builtin_override kf with
  | Some (name, builtin, spec) ->
    `Builtin (name, builtin, spec)
  | None ->
    if recursion_depth >= Parameters.RecursiveUnroll.get ()
    then begin
      Recursion.check_spec callsite kf;
      `Spec (get_funspec callsite kf)
    end
    else
      match kf.fundec with
      | Declaration _ -> `Spec (get_funspec callsite kf)
      | Definition (def, _) ->
        if Kernel_function.Set.mem kf (Parameters.UseSpec.get ())
        then `Spec (get_funspec callsite kf)
        else `Body (def, save_results def)

(* The registration of the hit log: see {!set_recorded_target}. *)
let recorded_target :
  (Callstack.t -> analysis_status -> (analysis_status * Callers.t) option) ref
  = ref (fun _ _ -> None)

let set_recorded_target f = recorded_target := f

(* While the hit log records, it gives the merged status and the callers,
   and the legacy tables are only written. *)
let register_analysis_target call analysis_target =
  Legacy_read_guard.reader "Eva.Function_calls.register_analysis_target"
  @@ fun () ->
  let status = status_of_target analysis_target in
  match !recorded_target call.callstack status with
  | Some (merged, callers) ->
    CallersTable.replace (Callstack.top_kf call.callstack) callers;
    StatusTable.replace call.kf merged
  | None ->
    register_call call;
    register_status call.kf status


type t = (analysis_status * Callers.t) Kernel_function.Map.t

let get_results () =
  Legacy_read_guard.notify Getter ~store:"analysis-status"
    (fun fmt -> Format.pp_print_string fmt "all functions");
  StatusTable.fold_sorted
    (fun kf status acc ->
       let callers = CallersTable.find kf in
       Kernel_function.Map.add kf (status, callers) acc)
    Kernel_function.Map.empty

let pretty fmt (results : t) =
  let pretty_status fmt = function
    | Unreachable -> Format.pp_print_string fmt "unreachable"
    | SpecUsed -> Format.pp_print_string fmt "specification used"
    | Builtin name -> Format.fprintf fmt "builtin %s" name
    | Analyzed Complete -> Format.pp_print_string fmt "analyzed complete"
    | Analyzed Partial -> Format.pp_print_string fmt "analyzed partial"
    | Analyzed NoResults ->
      Format.pp_print_string fmt "analyzed without results"
  in
  let pretty_caller fmt (caller, stmts) =
    Format.fprintf fmt "%a@@%a" Kernel_function.pretty caller
      (Pretty_utils.pp_list ~sep:"," Format.pp_print_int)
      (List.map (fun s -> Fileloc.line (Cil_datatype.Stmt.loc s))
         (StmtSet.elements stmts))
  in
  let pretty_function fmt (kf, (status, callers)) =
    Format.fprintf fmt "%a: %a; callers: %a" Kernel_function.pretty kf
      pretty_status status
      (Pretty_utils.pp_list ~sep:" " ~empty:"none" pretty_caller)
      (Kernel_function.Map.bindings callers)
  in
  Pretty_utils.pp_list ~sep:"@\n" pretty_function fmt
    (Kernel_function.Map.bindings results)

let make_results statuses relations =
  Kernel_function.Map.mapi (fun kf status ->
      let callers =
        Kernel_function.Map.find_opt kf relations
        |> Option.value ~default:Kernel_function.Map.empty
      in
      status, callers)
    statuses

let set_results =
  let register kf (status, callers) =
    StatusTable.replace kf status;
    CallersTable.replace kf callers
  in
  Kernel_function.Map.iter register
