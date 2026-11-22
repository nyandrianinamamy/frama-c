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

(* A call made by the body of the analysed call of a cache entry, at the call
   statement [site], to [callee]: [child] is the cache entry it used, computed
   or hit, if any; none for a call analysed by a specification or a builtin.
   [start] is its start state, projected on the blocks that the body had
   read or written before [site], on those that do not exist in the start
   state of the body (the blocks the body created), and on those that the
   call binds or removes (the formals and locals of [callee], and the blocks
   of the start state of the body that the start state of the call does not
   have). None if the footprint of the body is unknown. *)
type below = {
  site: Cil_types.stmt;
  callee: Cil_types.kernel_function;
  child: int option;
  start: point option;
}

module Below =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = below
      let name = "Eva.Hit_log.Below"
      let reprs =
        [ { site = Cil_datatype.Stmt.dummy;
            callee = List.hd Kernel_function.reprs;
            child = None; start = None } ]
      let structural_descr =
        let module Child = Datatype.Option (Datatype.Int) in
        let module Start = Datatype.Option (Point) in
        Structural_descr.t_record
          [| Cil_datatype.Stmt.packed_descr; Kernel_function.packed_descr;
             Child.packed_descr; Start.packed_descr |]
    end)

(* The points absent from the tables are unreachable. With an unknown
   footprint, no point is kept. *)
type inner_part =
  | Unknown
  | Known of { before: point Stmt_table.t; after: point Stmt_table.t }

(* States joined over some members of a key group, overall and per
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

(* The call that computed a cache entry. *)
type analysed = {
  callstack: Callstack.t;
  start: Cvalue.Model.t;
  body_entry: Cvalue.Model.t;
}

module Analysed =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = analysed
      let name = "Eva.Hit_log.Analysed"
      let reprs =
        [ { callstack = List.hd Callstack.reprs;
            start = Cvalue.Model.top; body_entry = Cvalue.Model.top } ]
      let structural_descr =
        Structural_descr.t_record
          [| Callstack.packed_descr; Cvalue.Model.packed_descr;
             Cvalue.Model.packed_descr |]
    end)

(* The key group of an entry is made of its analysed call, of its hits, and of
   the calls below a hit that use it. The states of the latter are computed on
   request from the entries of their callers. *)
type entry = {
  inner: inner_part;
  below: below list;
  analysed: analysed;
  hit_starts: states;
  hit_body_entries: states;
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
             { inner = Unknown; below = [];
               analysed = List.hd Analysed.reprs;
               hit_starts = states; hit_body_entries = states })
          States.reprs
      let structural_descr =
        let inner_part =
          Structural_descr.t_sum
            [| [| Points.packed_descr; Points.packed_descr |] |]
        in
        let module Below_list = Datatype.List (Below) in
        Structural_descr.t_record
          [| Structural_descr.pack inner_part;
             Below_list.packed_descr;
             Analysed.packed_descr;
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
  (* Functions whose body points are unavailable. *)
  body_unavailable: unit Kf_table.t;
  (* Whether a hit used an entry that was not recorded. Every request is then
     unavailable. *)
  mutable unrecorded_hit: bool;
}

let create () = {
  ended = false;
  initial = None;
  entries = Int_table.create 17;
  entries_of = Kf_table.create 17;
  other_starts = Kf_table.create 17;
  body_unavailable = Kf_table.create 7;
  unrecorded_hit = false;
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
  { inner; below = entry.below; analysed = entry.analysed;
    hit_starts = copy_states entry.hit_starts;
    hit_body_entries = copy_states entry.hit_body_entries }

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
    body_unavailable = Kf_table.copy store.body_unavailable;
    unrecorded_hit = store.unrecorded_hit; }

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
             Structural_descr.p_bool |]
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

(* A call being analysed, in any mode: the calls made by its body so far, each
   with its call statement, its function, its start state and the cache entry
   it used; and the cache entry this call uses, once known. *)
type frame = {
  mutable calls:
    (Cil_types.stmt * Cil_types.kernel_function * Cvalue.Model.t * int option)
      list;
  mutable used: int option;
}

(* The parts of the recording used only while the analysis runs. They are
   neither saved nor copied. *)
type running = {
  (* The calls being analysed, innermost first. *)
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

(* Projects [state] on the blocks of [zone], on those that do not belong to
   [existing], the blocks of the start state of the call, and on [bound]. *)
let project ?(bound = Base.Hptset.empty) ~existing zone state =
  let created = Base.Hptset.diff (bases_of_state state) existing in
  let covered = Base.Hptset.union (bases_of_zone zone) created in
  let covered = Base.Hptset.union covered bound in
  { covered; inner = Cvalue.Model.filter_by_shape covered state }

(* The blocks that a call to [callee] binds or removes, given its start state
   [state] and the blocks [existing] of the start state of the body that makes
   the call: the formals of [callee], bound by the call; its locals, absent
   from its start state; and the blocks of [existing] that [state] does not
   have. With unrolled recursive calls, the formals and locals of [callee] can
   exist in the state of the caller, in the frame of an outer call of
   [callee]: a recursive call removes them, or renames those whose address is
   taken, and binds the formals anew. *)
let bound_by_call ~existing callee state =
  let vars = Kernel_function.(get_formals callee @ get_locals callee) in
  let vars = Base.Hptset.of_list (List.map Base.of_varinfo vars) in
  let removed = Base.Hptset.diff existing (bases_of_state state) in
  Base.Hptset.union vars removed

(* Projects the states [before] and [after] each statement on the blocks
   covered at that point: those of the footprint, and the blocks that do not
   exist in the start state, created by the call. Projects the start states
   of the [calls] made by the body on the blocks covered before their call
   statement, on those that do not exist in the start state, and on those
   that the call binds or removes, see [bound_by_call].
   The state after a statement is the state at the point where it ends,
   which also receives the other paths that reach its successors: after a
   branch, the paths of the other branch; after a statement that is not an
   instruction, the join of the states before its successors. The footprint
   after a statement is thus completed by the footprints before its
   successors. *)
let inner_part footprint ~start ~before ~after ~calls =
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
  let project_all zone_of states =
    let points = Stmt_table.create (Stmt_table.length states) in
    let add stmt state =
      Stmt_table.replace points stmt (project ~existing (zone_of stmt) state)
    in
    Stmt_table.iter add states;
    points
  in
  let before = project_all zone_before (Lazy.force before) in
  let after = project_all zone_after (Lazy.force after) in
  let below =
    List.rev_map
      (fun (site, callee, state, child) ->
         let bound = bound_by_call ~existing callee state in
         let start = project ~bound ~existing (zone_before site) state in
         { site; callee; child; start = Some start })
      calls
  in
  Known { before; after }, below

(* ----- Recording --------------------------------------------------------- *)

let record_initial_state callstack state =
  (Store.get ()).initial <- Some (callstack, state)

let current_frame () =
  match (Running.get ()).frames with
  | [] -> None
  | frame :: _ -> Some frame

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

let record_analysed_call ~id callstack ~footprint ~start ~body_entry ~before
    ~after =
  let store = Store.get () in
  let kf = Callstack.top_kf callstack in
  let calls =
    match current_frame () with
    | None -> []
    | Some frame -> frame.used <- Some id; frame.calls
  in
  let unknown () =
    let below =
      List.rev_map
        (fun (site, callee, _, child) -> { site; callee; child; start = None })
        calls
    in
    Unknown, below
  in
  let inner, below =
    match footprint with
    | None -> unknown ()
    | Some footprint ->
      try inner_part footprint ~start ~before ~after ~calls
      with Unknown_footprint -> unknown ()
  in
  if inner = Unknown then mark store.body_unavailable kf;
  let entry = {
    inner;
    below;
    analysed = { callstack; start; body_entry };
    hit_starts = new_states ();
    hit_body_entries = new_states ();
  } in
  Int_table.replace store.entries id entry;
  let previous =
    Option.value ~default:[] (Kf_table.find_opt store.entries_of kf)
  in
  Kf_table.replace store.entries_of kf (id :: previous)

let record_hit ~id callstack ~start ~body_entry =
  let store = Store.get () in
  Option.iter (fun frame -> frame.used <- Some id) (current_frame ());
  match Int_table.find_opt store.entries id with
  | None -> store.unrecorded_hit <- true
  | Some entry ->
    add_state entry.hit_starts callstack start;
    add_state entry.hit_body_entries callstack body_entry

let mark_unrolled_recursion kf = mark (Store.get ()).body_unavailable kf

let mark_interrupted callstack ~start =
  record_start callstack start;
  mark (Store.get ()).body_unavailable (Callstack.top_kf callstack)

(* A call that an exception stops is interrupted, whatever the exception and
   wherever it is raised: in the body, by a hook, or before the body starts.
   Its function is marked, and so are those of the calls that make it, which
   the exception stops as well. *)
let call callstack ~start f =
  let running = Running.get () in
  let frame = { calls = []; used = None } in
  running.frames <- frame :: running.frames;
  let finally () =
    running.frames <- List.tl running.frames;
    match running.frames, Callstack.top_callsite callstack with
    | caller :: _, Kstmt site ->
      let call = site, Callstack.top_kf callstack, start, frame.used in
      caller.calls <- call :: caller.calls
    | _, Kglobal | [], _ -> ()
  in
  try Fun.protect ~finally f
  with exn ->
    let backtrace = Printexc.get_raw_backtrace () in
    mark_interrupted callstack ~start;
    Printexc.raise_with_backtrace exn backtrace

let analysis f =
  let finally () = if enabled () then (Store.get ()).ended <- true in
  Fun.protect ~finally f

(* ----- Calls below a hit ------------------------------------------------- *)

(* The calls below a hit never run. Their states are those of the calls made
   by the analysed call of the entry hit, as stored in this entry, pasted on
   the body-entry state of the hit. They are computed on request from the
   store, which does not change once the analysis has ended, and memoised.

   The members of an entry whose body did not run are its hits and the calls
   below a hit that use it. The calls made by their body are the calls below a
   hit. The body-entry states of these members are, joined: the joined
   body-entry state of the hits of the entry, joined with, for each call
   stored in an entry [parent] that used it, the stored start state of the
   call pasted on the body-entry states of the members of [parent] whose body
   did not run. The preconditions of a call below a hit are not evaluated: its
   body-entry state is its start state. Per callstack, the call below a member
   of [parent] on callstack [cs] is on the callstack [cs] extended with the
   call. An entry is completed after the entries its calls used: the
   recursion ends. *)

type derived = {
  (* The calls stored in the entries, with the number of the entry that
     stores them, by the entry they used. *)
  by_child: (int * below) list Int_table.t;
  (* The same calls, by the function they call. *)
  by_callee: (int * below) list Kf_table.t;
  (* For each entry, the body-entry states of its members whose body did not
     run, joined, and per callstack. *)
  unrun_joined: Cvalue.Model.t Int_table.t;
  unrun_by_callstack: Cvalue.Model.t Cs_table.t Int_table.t;
  (* For each function, the start states of the calls below a hit, joined,
     and per callstack. *)
  starts_joined: Cvalue.Model.t Kf_table.t;
  starts_by_callstack: Cvalue.Model.t Cs_table.t Kf_table.t;
  (* The answers to the requests joined over all callstacks, at the start of
     each function and before and after each statement. *)
  answers_start: Cvalue.Model.t Kf_table.t;
  answers_before: Cvalue.Model.t Stmt_table.t;
  answers_after: Cvalue.Model.t Stmt_table.t;
  mutable indexed: bool;
  mutable pastes: int;
}

let new_derived () = {
  by_child = Int_table.create 17;
  by_callee = Kf_table.create 17;
  unrun_joined = Int_table.create 17;
  unrun_by_callstack = Int_table.create 17;
  starts_joined = Kf_table.create 17;
  starts_by_callstack = Kf_table.create 17;
  answers_start = Kf_table.create 17;
  answers_before = Stmt_table.create 17;
  answers_after = Stmt_table.create 17;
  indexed = false;
  pastes = 0;
}

module Derived =
  State_builder.Ref
    (Datatype.Make
       (struct
         include Datatype.Undefined
         type t = derived
         let name = "Eva.Hit_log.Derived"
         let reprs = [ new_derived () ]
         let copy _ = new_derived ()
         let mem_project = Datatype.never_any_project
       end))
    (struct
      let name = "Eva.Hit_log.Derived"
      let dependencies = [ Store.self ]
      let default = new_derived
    end)

let derived store =
  let derived = Derived.get () in
  if not derived.indexed then begin
    let add table find key value =
      let previous = Option.value ~default:[] (find table key) in
      value :: previous
    in
    Int_table.iter
      (fun parent entry ->
         List.iter
           (fun below ->
              let call = parent, below in
              let callee = below.callee in
              Kf_table.replace derived.by_callee callee
                (add derived.by_callee Kf_table.find_opt callee call);
              Option.iter
                (fun child ->
                   Int_table.replace derived.by_child child
                     (add derived.by_child Int_table.find_opt child call))
                below.child)
           entry.below)
      store.entries;
    derived.indexed <- true
  end;
  derived

(* Raised when a call below a hit was stored without its start state. *)
exception Unavailable

(* The state at a point whose Inner part is [point], of a call whose
   body-entry state is [entry]: [entry] without the covered blocks, and the
   Inner part. Only the covered blocks that the Inner part does not bind are
   removed from [entry] before the Inner part is merged into it, so that the
   result shares the rest of [entry]. *)
let paste derived (point: point) entry =
  match entry, point.inner with
  | (Cvalue.Model.Bottom | Top), _ -> entry
  | Map _, (Cvalue.Model.Bottom | Top) ->
    derived.pastes <- derived.pastes + 1;
    point.inner
  | Map _, Cvalue.Model.Map inner ->
    derived.pastes <- derived.pastes + 1;
    let bound = Base.Hptset.from_map (Cvalue.Model.shape inner) in
    let unbound = Base.Hptset.diff point.covered bound in
    let frame = Base.Hptset.fold Cvalue.Model.remove_base unbound entry in
    Cvalue.Model.merge ~into:frame point.inner

(* The start state of the call [below] made by the body of a member whose
   body-entry state is [entry]. *)
let paste_call derived (below: below) entry =
  match below.start, entry with
  | _, Cvalue.Model.Bottom -> Cvalue.Model.bottom
  | None, _ -> raise Unavailable
  | Some start, _ -> paste derived start entry

let calls_of table find key =
  Option.value ~default:[] (find table key)

(* The joined body-entry state of the members of entry [id] whose body did
   not run. *)
let rec unrun_joined store derived id =
  match Int_table.find_opt derived.unrun_joined id with
  | Some state -> state
  | None ->
    let hits =
      match Int_table.find_opt store.entries id with
      | None -> Cvalue.Model.bottom
      | Some entry -> entry.hit_body_entries.joined
    in
    let state =
      List.fold_left
        (fun acc (parent, below) ->
           let entry = unrun_joined store derived parent in
           Cvalue.Model.join acc (paste_call derived below entry))
        hits (calls_of derived.by_child Int_table.find_opt id)
    in
    Int_table.replace derived.unrun_joined id state;
    state

(* Adds to [table], for each callstack of [states], the start state of the
   call [below] made by the body of the member of that callstack. *)
let add_calls_below derived table (below: below) states =
  Cs_table.iter
    (fun callstack entry ->
       let callstack = Callstack.push below.callee below.site callstack in
       let state = paste_call derived below entry in
       let state =
         match Cs_table.find_opt table callstack with
         | None -> state
         | Some previous -> Cvalue.Model.join previous state
       in
       Cs_table.replace table callstack state)
    states

(* The body-entry states of the members of entry [id] whose body did not run,
   per callstack. *)
let rec unrun_by_callstack store derived id =
  match Int_table.find_opt derived.unrun_by_callstack id with
  | Some table -> table
  | None ->
    let table =
      match Int_table.find_opt store.entries id with
      | None -> Cs_table.create 1
      | Some entry -> Cs_table.copy entry.hit_body_entries.by_callstack
    in
    List.iter
      (fun (parent, below) ->
         let states = unrun_by_callstack store derived parent in
         add_calls_below derived table below states)
      (calls_of derived.by_child Int_table.find_opt id);
    Int_table.replace derived.unrun_by_callstack id table;
    table

(* The start states of the calls below a hit to [kf], joined. *)
let starts_below_joined store derived kf =
  match Kf_table.find_opt derived.starts_joined kf with
  | Some state -> state
  | None ->
    let state =
      List.fold_left
        (fun acc (parent, below) ->
           let entry = unrun_joined store derived parent in
           Cvalue.Model.join acc (paste_call derived below entry))
        Cvalue.Model.bottom (calls_of derived.by_callee Kf_table.find_opt kf)
    in
    Kf_table.replace derived.starts_joined kf state;
    state

(* The start states of the calls below a hit to [kf], per callstack. *)
let starts_below_by_callstack store derived kf =
  match Kf_table.find_opt derived.starts_by_callstack kf with
  | Some table -> table
  | None ->
    let table = Cs_table.create 7 in
    List.iter
      (fun (parent, below) ->
         let states = unrun_by_callstack store derived parent in
         add_calls_below derived table below states)
      (calls_of derived.by_callee Kf_table.find_opt kf);
    Kf_table.replace derived.starts_by_callstack kf table;
    table

(* ----- The rule ---------------------------------------------------------- *)

let serving () = enabled () && (Store.get ()).ended

let to_result = function
  | Cvalue.Model.Bottom -> `Bottom
  | Top -> `Top
  | Map _ as state -> `Value state

let entries_of store kf =
  Option.value ~default:[] (Kf_table.find_opt store.entries_of kf)
  |> List.filter_map (Int_table.find_opt store.entries)

let entries_with_ids store kf =
  Option.value ~default:[] (Kf_table.find_opt store.entries_of kf)
  |> List.filter_map
    (fun id ->
       Option.map (fun entry -> id, entry) (Int_table.find_opt store.entries id))

(* The point of the Inner part of [entry] at [control_point], if reached. *)
let find_point entry control_point =
  match entry.inner, control_point with
  | Unknown, _ -> None
  | Known { before; _ }, Domain_store.Before stmt ->
    Stmt_table.find_opt before stmt
  | Known { after; _ }, After stmt -> Stmt_table.find_opt after stmt
  | Known _, (Initial | Start _) -> None

(* Whether the states of the cvalue domain are saved, by the condition of the
   legacy store. When they are not, every request is unavailable, as with the
   legacy store. *)
let cvalue_results_saved () =
  Parameters.(ResultsAll.get ()
              && not (NoResultsDomain.mem Cvalue_domain.State.name))

let is_available store control_point =
  cvalue_results_saved () && not store.unrecorded_hit &&
  match control_point with
  | Domain_store.Initial | Start _ -> true
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    not (Kf_table.mem store.body_unavailable kf)

let available control_point = is_available (Store.get ()) control_point

let join_all list = List.fold_left Cvalue.Model.join Cvalue.Model.bottom list

let find_callstack table callstack =
  Option.value ~default:Cvalue.Model.bottom (Cs_table.find_opt table callstack)

(* The state of the analysed call of [entry] if it is on [callstack]. *)
let analysed_on callstack get entry =
  if Callstack.equal entry.analysed.callstack callstack
  then get entry.analysed
  else Cvalue.Model.bottom

(* Reports the number of pastes made by a request. *)
let count_pastes derived f =
  let before = derived.pastes in
  let result = f () in
  Self.debug ~dkey:Log_key.debug_hit_log "pastes made by the request: %d"
    (derived.pastes - before);
  result

let start_state store derived ?callstack kf =
  let entries = entries_of store kf in
  let others = Option.to_list (Kf_table.find_opt store.other_starts kf) in
  match callstack with
  | None ->
    List.map (fun entry -> entry.analysed.start) entries
    @ List.map (fun entry -> entry.hit_starts.joined) entries
    @ List.map (fun states -> states.joined) others
    @ [ starts_below_joined store derived kf ]
    |> join_all
  | Some callstack ->
    let find states = find_callstack states.by_callstack callstack in
    List.map (analysed_on callstack (fun a -> a.start)) entries
    @ List.map (fun entry -> find entry.hit_starts) entries
    @ List.map find others
    @ [ find_callstack (starts_below_by_callstack store derived kf) callstack ]
    |> join_all

let point_state store derived ?callstack control_point kf =
  let state (id, entry) =
    match find_point entry control_point with
    | None -> Cvalue.Model.bottom
    | Some point ->
      let body_entry =
        match callstack with
        | None ->
          Cvalue.Model.join entry.analysed.body_entry
            (unrun_joined store derived id)
        | Some callstack ->
          Cvalue.Model.join
            (analysed_on callstack (fun a -> a.body_entry) entry)
            (find_callstack (unrun_by_callstack store derived id) callstack)
      in
      paste derived point body_entry
  in
  List.map state (entries_with_ids store kf) |> join_all

(* [memo table find replace key f] is the answer [f ()] for [key], memoised
   in [table]. *)
let memo table find replace key f =
  match find table key with
  | Some state -> state
  | None ->
    let state = f () in
    replace table key state;
    state

let get_state ?callstack control_point =
  let store = Store.get () in
  if not (is_available store control_point) then `Top
  else
    let derived = derived store in
    count_pastes derived @@ fun () ->
    let point_state stmt table =
      let kf = Kernel_function.find_englobing_kf stmt in
      let compute () = point_state store derived ?callstack control_point kf in
      match callstack with
      | Some _ -> compute ()
      | None -> memo table Stmt_table.find_opt Stmt_table.replace stmt compute
    in
    try
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
        let compute () = start_state store derived ?callstack kf in
        begin match callstack with
          | Some _ -> to_result (compute ())
          | None ->
            memo derived.answers_start Kf_table.find_opt Kf_table.replace kf
              compute
            |> to_result
        end
      | Before stmt -> to_result (point_state stmt derived.answers_before)
      | After stmt -> to_result (point_state stmt derived.answers_after)
    with Unavailable -> `Top

(* Joins [state] into the state of [callstack] in [table]. *)
let add table callstack state =
  let state =
    match Cs_table.find_opt table callstack with
    | None -> state
    | Some previous -> Cvalue.Model.join previous state
  in
  Cs_table.replace table callstack state

let states_by_callstack store derived control_point =
  let table = Cs_table.create 17 in
  begin match control_point with
    | Domain_store.Initial ->
      Option.iter (fun (callstack, state) -> add table callstack state)
        store.initial
    | Start kf ->
      let add_all states = Cs_table.iter (add table) states.by_callstack in
      List.iter
        (fun entry ->
           add table entry.analysed.callstack entry.analysed.start;
           add_all entry.hit_starts)
        (entries_of store kf);
      Option.iter add_all (Kf_table.find_opt store.other_starts kf);
      Cs_table.iter (add table) (starts_below_by_callstack store derived kf)
    | Before stmt | After stmt ->
      let kf = Kernel_function.find_englobing_kf stmt in
      List.iter
        (fun (id, entry) ->
           match find_point entry control_point with
           | None -> ()
           | Some point ->
             let analysed = entry.analysed in
             add table analysed.callstack
               (paste derived point analysed.body_entry);
             Cs_table.iter
               (fun callstack state ->
                  add table callstack (paste derived point state))
               (unrun_by_callstack store derived id))
        (entries_with_ids store kf)
  end;
  table

let get_state_by_callstack control_point =
  let store = Store.get () in
  if not (is_available store control_point) then `Top
  else
    let derived = derived store in
    count_pastes derived @@ fun () ->
    try
      let table = states_by_callstack store derived control_point in
      let reached =
        Cs_table.fold
          (fun callstack state acc ->
             match state with
             | Cvalue.Model.Bottom -> acc
             | Top | Map _ -> (callstack, state) :: acc)
          table []
      in
      match List.sort (fun (a, _) (b, _) -> Callstack.compare a b) reached with
      | [] -> `Bottom
      | list -> `Value list
    with Unavailable -> `Top
