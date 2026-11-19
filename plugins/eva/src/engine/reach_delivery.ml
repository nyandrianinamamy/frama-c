(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module ControlPoint = Domain_store.ControlPoint

(* The callstacks of the hits that reached each control point. *)
module Points =
  State_builder.Hashtbl (ControlPoint.Hashtbl) (Callstack.Set)
    (struct
      let name = "Eva.Reach_delivery.Points"
      let size = 17
      let dependencies = [ Self.state ]
    end)

let add_point point callstack =
  let add = function
    | None -> Callstack.Set.singleton callstack
    | Some set -> Callstack.Set.add callstack set
  in
  Points.replace point (add (Points.find_opt point))

let reached ?callstack point =
  Points.length () > 0
  &&
  match Points.find_opt point, callstack with
  | None, _ -> false
  | Some _, None -> true
  | Some set, Some callstack -> Callstack.Set.mem callstack set

let callstacks point =
  match Points.find_opt point with
  | None -> []
  | Some set -> Callstack.Set.elements set

let deliver callstack ~save_results part =
  let deliver_write (write : Reach_part.write) =
    match write with
    | Reached { point; frames } ->
      if save_results then begin
        let callstack = Reach_part.reroot callstack frames in
        Reach_part.record_state callstack point;
        add_point point callstack
      end
    | Guard { stmt; outcome } -> Iterator.add_condition stmt outcome
    | Zones { stmt; frames; read; write } ->
      let position = Position.local stmt (Reach_part.reroot callstack frames) in
      Inout_access.register position (Inout_access.Access.make ~read ~write ())
    | Caller { frames } ->
      Function_calls.register_caller (Reach_part.reroot callstack frames)
  in
  List.iter deliver_write part

(* ----- Functions of unknown reachability --------------------------------- *)

module Unknown =
  State_builder.Set_ref (Kernel_function.Set)
    (struct
      let name = "Eva.Reach_delivery.Unknown"
      let dependencies = [ Self.state ]
    end)

let reach_unknown = Unknown.add

let reach_unknown_of kf = not (Unknown.is_empty ()) && Unknown.mem kf

let reach_unknown_at stmt =
  not (Unknown.is_empty ())
  && Unknown.mem (Kernel_function.find_englobing_kf stmt)
