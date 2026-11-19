(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

module Entry = Cache_entry.Cvalue
module Blocks = Base.Hptset

type call_mode = Body_access.call_mode

type entry = {
  cache_entry : Entry.t;
  recorded : Body_access.Result.recorded list;
  inner : Callstack.t option;
  dependencies : Cache_entry.dependencies;
}

let cache_entry e = e.cache_entry
let recorded e = e.recorded
let inner e = e.inner
let sweeps e = e.dependencies.sweeps
let hint_generation e = e.dependencies.hint_generation
let used_functions e = e.dependencies.used_functions

module Entries = Datatype.Make (struct
    include Datatype.Undefined
    type t = entry list
    let name = "Eva.Cache_producer.Entries"
    let reprs = [ [] ]
    let mem_project = Datatype.never_any_project
  end)

module Table =
  Kernel_function.Make_Table
    (Eva_utils.Do_Not_Marshal (Entries))
    (struct
      let name = "Eva.Cache_producer.Table"
      let dependencies = [ Self.state ]
      let size = 17
    end)

module Counter =
  State_builder.Counter (struct let name = "Eva.Cache_producer.Counter" end)

let () = Cvalue_callbacks.register_at_start_hook Counter.reset

let newest_first kf = Option.value ~default:[] (Table.find_opt kf)
let entries kf = List.rev (newest_first kf)

type refusal =
  | Product | Collector of Body_access.Result.refusal
  | Footprint_top | Invalid_footprint | Relate_top | Key_limit
  | Preconditions | Not_cacheable | Input_state | Exit_state | Exit_binding

let refusal_id = function
  | Product -> "product"
  | Collector reason -> Body_access.Result.refusal_id reason
  | Footprint_top -> "footprint-top"
  | Invalid_footprint -> "invalid-footprint"
  | Relate_top -> "relate-top"
  | Key_limit -> "key-limit"
  | Preconditions -> "preconditions"
  | Not_cacheable -> "not-cacheable"
  | Input_state -> "input-state"
  | Exit_state -> "exit-state"
  | Exit_binding -> "exit-binding"

let footprint (r : Body_access.Result.t) =
  match r.reads, r.writes, r.exit_writes with
  | Set read, Set written, Set written_exit ->
    let footprint =
      Cache_entry.{ read; written; written_exit; written_sure = r.sure_writes }
    in
    if Cache_entry.valid_footprint footprint then Ok footprint
    else Error Invalid_footprint
  | _ -> Error Footprint_top

let key_seed reads (footprint : Cache_entry.footprint) =
  let add_variable b key =
    match Base.validity b with
    | Base.Variable _ -> Blocks.add b key
    | _ -> key
  in
  Blocks.fold add_variable footprint.written_exit
    (Cache_entry.required_key ~reads footprint)

let close_key input =
  let limit = Parameters.CacheKeyLimit.get () in
  let rec close key =
    if Blocks.cardinal key > limit then Error Key_limit
    else
      match Cvalue_domain.State.relate key input with
      (* Defensive: cvalue's relation currently returns the empty set. *)
      | Top -> Error Relate_top
      | Set related when Blocks.subset related key -> Ok key
      | Set related -> close (Blocks.union related key)
  in
  close

let is_map = function
  | Cvalue.Model.Map _ -> true
  | Top | Bottom -> false

let binds model b =
  match Cvalue.Model.find_base b model with
  | `Value _ -> true
  | `Bottom | `Top -> false
  | exception Not_found -> false

let has_preconditions kf =
  (* The observer excludes requires checks, and a supplied hit does not use
     their reduced states. Record an entry only when there is no such check. *)
  not (Eva_utils.skip_specifications kf)
  && List.exists (fun b -> b.b_requires <> [])
    (Annotations.funspec kf).spec_behavior

let produce ~save_results callstack input states r =
  let open Result in
  let ( let* ) = bind in
  let kf = Callstack.top_kf callstack in
  let statement = Cache_entry.Body kf in
  let* footprint = footprint r in
  let footprint = Cache_entry.with_return_block statement footprint in
  let* reads =
    match r.Body_access.Result.dependencies with
    | Set blocks -> Ok blocks
    | Top -> Error Footprint_top
  in
  let key = Blocks.union r.sweeps (key_seed reads footprint) in
  let* key = close_key input key in
  let replayable model b =
    binds model b || (Blocks.mem b r.sweeps && not (binds (fst input) b))
  in
  if not (is_map (fst input)) then Error Input_state
  else if not (List.for_all (fun (_, (m, _)) -> is_map m) states) then
    Error Exit_state
  else if not (List.for_all
                 (fun (_, (m, _)) ->
                    Blocks.for_all (replayable m) footprint.written_exit)
                 states)
  then Error Exit_binding
  else begin
    (* Eva accumulates holders in a mutable cell shared with the caller. *)
    let copy (model, holders) =
      model, Locals_scoping.{ clob = holders.clob }
    in
    let exit = List.map (fun (k, state) -> k, copy state) states in
    let id = Counter.get () + 1 in
    let dependencies = Cache_entry.{
        sweeps = r.sweeps; hint_generation = r.hint_generation;
        used_functions = r.used_functions;
      }
    in
    let observation =
      Cache_observation.{ designated = r.designated; recorded = r.recorded }
    in
    let cache_entry =
      Entry.make ~id ~reads ~dependencies ~observation ~children:r.children
        statement ~key ~input:(copy input) ~footprint ~exit
    in
    let inner =
      if save_results && Cvalue_domain.State.Store.is_computed ()
      then Some callstack
      else None
    in
    let entry = {
      cache_entry; recorded = r.recorded; inner; dependencies;
    } in
    ignore (Counter.next ());
    Table.replace kf (entry :: newest_first kf);
    Ok cache_entry
  end

module Make (Domain : sig
    type t
    val structure : t Abstract.Domain.structure
  end) = struct

  let cvalue_alone : (Domain.t, Cvalue_domain.State.t) Structure.eq option =
    match Domain.structure with
    | Abstract.Domain.Leaf (key, _) ->
      Structure.Key_Domain.eq_type key Cvalue_domain.State.key
    | _ -> None

  let store ~save_results callstack (input : Domain.t)
      (result : Domain.t Engine_sig.call_result) observation verdict =
    match cvalue_alone with
    | None -> Error Product
    | Some Structure.Eq ->
      match verdict with
      | Error reason -> Error (Collector reason)
      | Ok () ->
        if result.cacheable <> Eval.Cacheable then Error Not_cacheable
        else if has_preconditions (Callstack.top_kf callstack) then
          Error Preconditions
        else produce ~save_results callstack input result.states observation
end
