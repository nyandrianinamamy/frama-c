(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Stmt_table = Cil_datatype.Stmt.Hashtbl
module Kf_table = Kernel_function.Hashtbl
module Cs_table = Callstack.Hashtbl

let enabled () = Parameters.HitLog.get ()

let check_configuration () =
  if enabled () then
    let cvalue_only =
      Abstractions.Config.of_list [ Cvalue_domain.registered, None ]
    in
    if not (Abstractions.Config.(equal (configure ()) cvalue_only)) then
      Self.abort "Option %s requires the cvalue domain alone."
        Parameters.HitLog.option_name

(* ----- Store ------------------------------------------------------------- *)

(* The store is saved with the project, and thus kept by a copy of the
   project, which is made by saving and loading it. *)

module Int_table = Datatype.Int.Hashtbl

(* The state at a point of the Inner part: [inner] is the state projected on
   the blocks of [covered]. A covered block that [inner] does not bind has no
   binding at this point. *)
type point = {
  covered: Base.Hptset.t;
  inner: Cvalue.Model.t;
}

module Point =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = point
      let name = "Eva.Hit_log.Point"
      let reprs = [ { covered = Base.Hptset.empty; inner = Cvalue.Model.top } ]
      let structural_descr =
        Structural_descr.t_record
          [| Base.Hptset.packed_descr; Cvalue.Model.packed_descr |]
    end)

module Points = Stmt_table.Make (Point)

(* The points absent from the tables are unreachable. With an unknown
   footprint, no point is kept. *)
type inner_part =
  | Unknown
  | Known of { before: point Stmt_table.t; after: point Stmt_table.t }

(* States joined over the members of a key group, overall and per
   callstack. *)
type states = {
  mutable joined: Cvalue.Model.t;
  by_callstack: Cvalue.Model.t Cs_table.t;
}

module States =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = states
      let name = "Eva.Hit_log.States"
      let reprs =
        [ { joined = Cvalue.Model.bottom; by_callstack = Cs_table.create 1 } ]
      let structural_descr =
        let module By_callstack = Cs_table.Make (Cvalue.Model) in
        Structural_descr.t_record
          [| Cvalue.Model.packed_descr; By_callstack.packed_descr |]
    end)

type entry = {
  inner: inner_part;
  (* The functions called while the entry was computed, in any mode, and
     those called while the entries used by these calls were computed. *)
  mutable called: Kernel_function.Set.t;
  starts: states;
  body_entries: states;
}

module Entry =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = entry
      let name = "Eva.Hit_log.Entry"
      let reprs =
        List.map
          (fun states ->
             { inner = Unknown; called = Kernel_function.Set.empty;
               starts = states; body_entries = states })
          States.reprs
      let structural_descr =
        let inner_part =
          Structural_descr.t_sum
            [| [| Points.packed_descr; Points.packed_descr |] |]
        in
        Structural_descr.t_record
          [| Structural_descr.pack inner_part;
             Kernel_function.Set.packed_descr;
             States.packed_descr;
             States.packed_descr |]
    end)

type store = {
  mutable ended: bool;
  mutable initial: (Callstack.t * Cvalue.Model.t) option;
  (* The cache entries, by number. *)
  entries: entry Int_table.t;
  (* The numbers of the cache entries of each function. *)
  entries_of: int list Kf_table.t;
  (* Start states of the calls analysed by a specification or a builtin. *)
  other_starts: states Kf_table.t;
  (* Functions unavailable at every point. *)
  below_hit: unit Kf_table.t;
  (* Functions whose body points are unavailable. *)
  body_unavailable: unit Kf_table.t;
}

let create () = {
  ended = false;
  initial = None;
  entries = Int_table.create 17;
  entries_of = Kf_table.create 17;
  other_starts = Kf_table.create 17;
  below_hit = Kf_table.create 7;
  body_unavailable = Kf_table.create 7;
}

let copy_states states =
  { joined = states.joined; by_callstack = Cs_table.copy states.by_callstack }

let copy_entry entry =
  let inner =
    match entry.inner with
    | Unknown -> Unknown
    | Known { before; after } ->
      Known { before = Stmt_table.copy before; after = Stmt_table.copy after }
  in
  { inner; called = entry.called;
    starts = copy_states entry.starts;
    body_entries = copy_states entry.body_entries }

let copy_store store =
  let entries = Int_table.create (Int_table.length store.entries) in
  Int_table.iter
    (fun id entry -> Int_table.replace entries id (copy_entry entry))
    store.entries;
  let other_starts = Kf_table.create (Kf_table.length store.other_starts) in
  Kf_table.iter
    (fun kf states -> Kf_table.replace other_starts kf (copy_states states))
    store.other_starts;
  { ended = store.ended;
    initial = store.initial;
    entries;
    entries_of = Kf_table.copy store.entries_of;
    other_starts;
    below_hit = Kf_table.copy store.below_hit;
    body_unavailable = Kf_table.copy store.body_unavailable; }

module Store_datatype =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = store
      let name = "Eva.Hit_log.Store"
      let reprs = [ create () ]
      let structural_descr =
        let module Initial =
          Datatype.Option (Datatype.Pair (Callstack) (Cvalue.Model))
        in
        let module Entries = Int_table.Make (Entry) in
        let module Entries_of = Kf_table.Make (Datatype.List (Datatype.Int)) in
        let module States_of = Kf_table.Make (States) in
        let module Marks = Kf_table.Make (Datatype.Unit) in
        Structural_descr.t_record
          [| Structural_descr.p_bool;
             Initial.packed_descr;
             Entries.packed_descr;
             Entries_of.packed_descr;
             States_of.packed_descr;
             Marks.packed_descr;
             Marks.packed_descr |]
      let copy = copy_store
    end)

module Store =
  State_builder.Ref
    (Store_datatype)
    (struct
      let name = "Eva.Hit_log.Store"
      let dependencies = [ Self.state ]
      let default = create
    end)

let new_states () =
  { joined = Cvalue.Model.bottom; by_callstack = Cs_table.create 7 }

let add_state states callstack state =
  states.joined <- Cvalue.Model.join states.joined state;
  let state =
    match Cs_table.find_opt states.by_callstack callstack with
    | None -> state
    | Some previous -> Cvalue.Model.join previous state
  in
  Cs_table.replace states.by_callstack callstack state

let mark table kf = Kf_table.replace table kf ()

(* ----- The analysis being run -------------------------------------------- *)

(* The memory read or written before and after each statement of a body. *)
type footprint = Cil_types.stmt -> Memory_zone.t * Memory_zone.t

(* The call of the current project whose hooks of the end of call are being
   run, identified by the number of its cache entry, with the footprint given
   so far for it. A footprint given for another call is ignored. *)
type slot =
  | Closed
  | Open of { id: int; mutable footprint: footprint option }

(* A body being analysed: the functions it calls, and its cache entry once
   recorded. *)
type frame = {
  mutable called_below: Kernel_function.Set.t;
  mutable entry: entry option;
}

(* The parts of the recording used only while the analysis runs. They are
   neither saved nor copied. *)
type running = {
  (* The bodies being analysed, innermost first. *)
  mutable frames: frame list;
  mutable slot: slot;
}

let new_running () = { frames = []; slot = Closed }

module Running =
  State_builder.Ref
    (Datatype.Make
       (struct
         include Datatype.Undefined
         type t = running
         let name = "Eva.Hit_log.Running"
         let reprs = [ new_running () ]
         let copy _ = new_running ()
         let mem_project = Datatype.never_any_project
       end))
    (struct
      let name = "Eva.Hit_log.Running"
      let dependencies = [ Self.state ]
      let default = new_running
    end)

(* ----- Footprint given by the inout plugin ------------------------------- *)

let offer_footprint (id, footprint) =
  if enabled () then
    match (Running.get ()).slot with
    | Open slot when slot.id = id -> slot.footprint <- Some footprint
    | Open _ | Closed -> ()

let () =
  Cmdline.run_after_configuring_stage
    (fun () -> Eva_dynamic.Inout.register_footprint_hook offer_footprint)

let footprint_of_call ~id hooks =
  let running = Running.get () in
  let outer = running.slot in
  let slot = Open { id; footprint = None } in
  running.slot <- slot;
  Fun.protect ~finally:(fun () -> running.slot <- outer) hooks;
  match slot with
  | Open { footprint; _ } -> footprint
  | Closed -> None

exception Unknown_footprint

let bases_of_zone = function
  | Memory_zone.Top (Base.SetLattice.Top, _) -> raise Unknown_footprint
  | Memory_zone.Top (Base.SetLattice.Set bases, _) -> bases
  | Memory_zone.Map map -> Base.Hptset.from_map (Memory_zone.shape map)

let bases_of_state = function
  | Cvalue.Model.Bottom -> Base.Hptset.empty
  | Top -> raise Unknown_footprint
  | Map map -> Base.Hptset.from_map (Cvalue.Model.shape map)

(* Projects the states [before] and [after] each statement on the blocks
   covered at that point: those of the footprint, and the blocks that do not
   exist in the start state [start], created by the call.
   The state after a statement is the state at the point where it ends,
   which also receives the other paths that reach its successors: after a
   branch, the paths of the other branch; after a statement that is not an
   instruction, the join of the states before its successors. The footprint
   after a statement is thus completed by the footprints before its
   successors. *)
let inner_part footprint ~start ~before ~after =
  let existing = bases_of_state start in
  let footprints = Stmt_table.create 17 in
  let footprint stmt =
    match Stmt_table.find_opt footprints stmt with
    | Some zones -> zones
    | None ->
      let zones = footprint stmt in
      Stmt_table.replace footprints stmt zones;
      zones
  in
  let zone_before stmt = fst (footprint stmt) in
  let zone_after stmt =
    let succs = List.map zone_before stmt.Cil_types.succs in
    List.fold_left Memory_zone.join (snd (footprint stmt)) succs
  in
  let project zone state =
    let created = Base.Hptset.diff (bases_of_state state) existing in
    let covered = Base.Hptset.union (bases_of_zone zone) created in
    { covered; inner = Cvalue.Model.filter_by_shape covered state }
  in
  let project_all zone_of states =
    let points = Stmt_table.create (Stmt_table.length states) in
    let add stmt state =
      Stmt_table.replace points stmt (project (zone_of stmt) state)
    in
    Stmt_table.iter add states;
    points
  in
  let before = project_all zone_before (Lazy.force before) in
  let after = project_all zone_after (Lazy.force after) in
  Known { before; after }

(* ----- Recording --------------------------------------------------------- *)

let record_initial_state callstack state =
  (Store.get ()).initial <- Some (callstack, state)

let record_call kf =
  match (Running.get ()).frames with
  | [] -> ()
  | frame :: _ ->
    frame.called_below <- Kernel_function.Set.add kf frame.called_below

let add_below called =
  match (Running.get ()).frames with
  | [] -> ()
  | frame :: _ ->
    frame.called_below <- Kernel_function.Set.union called frame.called_below

let record_start callstack state =
  let store = Store.get () in
  let kf = Callstack.top_kf callstack in
  let states =
    match Kf_table.find_opt store.other_starts kf with
    | Some states -> states
    | None ->
      let states = new_states () in
      Kf_table.replace store.other_starts kf states;
      states
  in
  add_state states callstack state

let analyse_body f =
  let running = Running.get () in
  let frame = { called_below = Kernel_function.Set.empty; entry = None } in
  running.frames <- frame :: running.frames;
  let finally () =
    running.frames <- List.tl running.frames;
    Option.iter (fun entry -> entry.called <- frame.called_below) frame.entry;
    add_below frame.called_below
  in
  Fun.protect ~finally f

let record_analysed_call ~id callstack ~footprint ~start ~body_entry ~before
    ~after =
  let store = Store.get () in
  let kf = Callstack.top_kf callstack in
  let inner =
    match footprint with
    | None -> Unknown
    | Some footprint ->
      try inner_part footprint ~start ~before ~after
      with Unknown_footprint -> Unknown
  in
  if inner = Unknown then mark store.body_unavailable kf;
  let entry = {
    inner;
    called = Kernel_function.Set.empty;
    starts = new_states ();
    body_entries = new_states ();
  } in
  add_state entry.starts callstack start;
  add_state entry.body_entries callstack body_entry;
  Int_table.replace store.entries id entry;
  let previous =
    Option.value ~default:[] (Kf_table.find_opt store.entries_of kf)
  in
  Kf_table.replace store.entries_of kf (id :: previous);
  match (Running.get ()).frames with
  | [] -> ()
  | frame :: _ -> frame.entry <- Some entry

let record_hit ~id callstack ~start ~body_entry =
  let store = Store.get () in
  match Int_table.find_opt store.entries id with
  | None ->
    (* The entry was not recorded: nothing is answered for this function. *)
    mark store.below_hit (Callstack.top_kf callstack)
  | Some entry ->
    add_state entry.starts callstack start;
    add_state entry.body_entries callstack body_entry;
    Kernel_function.Set.iter (mark store.below_hit) entry.called;
    add_below entry.called

let mark_unrolled_recursion kf = mark (Store.get ()).body_unavailable kf

let mark_interrupted callstack ~start =
  record_start callstack start;
  mark (Store.get ()).body_unavailable (Callstack.top_kf callstack)

let analysis f =
  let finally () = if enabled () then (Store.get ()).ended <- true in
  Fun.protect ~finally f

(* ----- The rule ---------------------------------------------------------- *)

let serving () = enabled () && (Store.get ()).ended

let to_result = function
  | Cvalue.Model.Bottom -> `Bottom
  | Top -> `Top
  | Map _ as state -> `Value state

(* The state at a point of a call whose body-entry state is [entry]. *)
let paste point entry =
  match entry with
  | Cvalue.Model.Bottom | Top -> entry
  | Map _ ->
    let not_covered base = not (Base.Hptset.mem base point.covered) in
    let frame = Cvalue.Model.filter_base not_covered entry in
    Cvalue.Model.merge ~into:frame point.inner

let select callstack states =
  match callstack with
  | None -> states.joined
  | Some callstack ->
    Option.value ~default:Cvalue.Model.bottom
      (Cs_table.find_opt states.by_callstack callstack)

let entries_of store kf =
  Option.value ~default:[] (Kf_table.find_opt store.entries_of kf)
  |> List.filter_map (Int_table.find_opt store.entries)

(* The start states of the calls to [kf]. *)
let starts store kf =
  let others = Option.to_list (Kf_table.find_opt store.other_starts kf) in
  List.map (fun entry -> entry.starts) (entries_of store kf) @ others

(* The point of the Inner part of [entry] at [control_point], if reached. *)
let find_point entry control_point =
  match entry.inner, control_point with
  | Unknown, _ -> None
  | Known { before; _ }, Domain_store.Before stmt ->
    Stmt_table.find_opt before stmt
  | Known { after; _ }, After stmt -> Stmt_table.find_opt after stmt
  | Known _, (Initial | Start _) -> None

type availability = Available | Unavailable

let availability store = function
  | Domain_store.Initial -> Available
  | Start kf ->
    if Kf_table.mem store.below_hit kf then Unavailable else Available
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    if Kf_table.(mem store.below_hit kf || mem store.body_unavailable kf)
    then Unavailable
    else Available

let join_all list = List.fold_left Cvalue.Model.join Cvalue.Model.bottom list

let get_state ?callstack control_point =
  let store = Store.get () in
  match availability store control_point with
  | Unavailable -> `Top
  | Available ->
    match control_point with
    | Initial ->
      begin match store.initial, callstack with
        | None, _ -> `Bottom
        | Some (_, state), None -> to_result state
        | Some (initial, state), Some callstack ->
          if Callstack.equal initial callstack then to_result state
          else `Bottom
      end
    | Start kf ->
      List.map (select callstack) (starts store kf) |> join_all |> to_result
    | Before stmt | After stmt ->
      let kf = Kernel_function.find_englobing_kf stmt in
      let state entry =
        match find_point entry control_point with
        | None -> Cvalue.Model.bottom
        | Some point -> paste point (select callstack entry.body_entries)
      in
      List.map state (entries_of store kf) |> join_all |> to_result

let get_state_by_callstack control_point =
  let store = Store.get () in
  match availability store control_point with
  | Unavailable -> `Top
  | Available ->
    let callstacks =
      match control_point with
      | Initial -> Option.to_list (Option.map fst store.initial)
      | Start kf ->
        let keys states =
          List.of_seq (Cs_table.to_seq_keys states.by_callstack)
        in
        List.concat_map keys (starts store kf)
      | Before stmt | After stmt ->
        let kf = Kernel_function.find_englobing_kf stmt in
        let keys entry =
          List.of_seq (Cs_table.to_seq_keys entry.body_entries.by_callstack)
        in
        List.concat_map keys (entries_of store kf)
    in
    let callstacks = List.sort_uniq Callstack.compare callstacks in
    let state callstack =
      match get_state ~callstack control_point with
      | `Bottom -> None
      | `Top -> Some (callstack, Cvalue.Model.top)
      | `Value state -> Some (callstack, state)
    in
    match List.filter_map state callstacks with
    | [] -> `Bottom
    | list -> `Value list
