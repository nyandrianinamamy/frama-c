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

let deliver_write callstack (write : Reach_part.write) =
  match write with
  | Reached { point; frames } ->
    let callstack = Reach_part.reroot callstack frames in
    Reach_part.record_state callstack point;
    add_point point callstack
  | Guard { stmt; outcome } -> Iterator.add_condition stmt outcome
  | Zones { stmt; frames; read; write } ->
    let position = Position.local stmt (Reach_part.reroot callstack frames) in
    Inout_access.register position (Inout_access.Access.make ~read ~write ())
  | Caller { frames } ->
    Function_calls.register_caller (Reach_part.reroot callstack frames)

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

(* ----- Delivery ---------------------------------------------------------- *)

(* The lookup rejects a part without points where the states of the
   function are saved ([`Missing_points]), with the same [save_results].
   A hit requires the cvalue domain alone: its store is the store of the
   states that the queries read. When it saves no state, as under
   [-eva-no-results-domain cvalue], the queries answer no callstack at any
   point, and the points of the hit are not seen. *)
let deliver callstack ~save_results (part : Reach_part.part) =
  List.iter (deliver_write callstack) part.joins;
  if save_results then begin
    match part.points with
    | Some points -> List.iter (deliver_write callstack) points
    | None -> assert false
  end;
  if save_results && not (Cvalue_domain.State.Store.is_computed ())
  then reach_unknown (Callstack.top_kf callstack)

(* ----- Saved results ----------------------------------------------------- *)

type records = {
  points : (Domain_store.control_point * Callstack.Set.t) list;
  unknown : Kernel_function.Set.t;
  skipped : Kernel_function.t list;
}

let records () =
  let skipped kf acc =
    if Safety_delivery.visits_skipped kf then kf :: acc else acc
  in
  { points = Points.fold (fun point set acc -> (point, set) :: acc) [];
    unknown = Unknown.get ();
    skipped = Globals.Functions.fold skipped [] }

let restore records =
  let add (point, set) =
    let union = function
      | None -> set
      | Some previous -> Callstack.Set.union previous set
    in
    Points.replace point (union (Points.find_opt point))
  in
  List.iter add records.points;
  Kernel_function.Set.iter reach_unknown records.unknown;
  List.iter Safety_delivery.skip_visits records.skipped
