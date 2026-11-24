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
   binding at this point: the removal mask. [swept_every] and [swept_some]
   are the sweep map: the blocks that a release swept on every path from the
   start of the body to the point, and those swept on some path only, see
   [Heap_paths]. Empty except for a heap call. *)
type point = {
  covered: Base.Hptset.t;
  inner: Cvalue.Model.t;
  swept_every: Base.Hptset.t;
  swept_some: Base.Hptset.t;
}

module Point =
  Datatype.Make
    (struct
      include Datatype.Serializable_undefined
      type t = point
      let name = "Eva.Hit_log.Point"
      let reprs =
        [ { covered = Base.Hptset.empty; inner = Cvalue.Model.top;
            swept_every = Base.Hptset.empty; swept_some = Base.Hptset.empty } ]
      let structural_descr =
        Structural_descr.t_record
          [| Base.Hptset.packed_descr; Cvalue.Model.packed_descr;
             Base.Hptset.packed_descr; Base.Hptset.packed_descr |]
    end)

module Points = Stmt_table.Make (Point)

(* A renaming of the allocated blocks of a cache entry: pairs of blocks,
   from the blocks of the analysed call of the entry to those of a call that
   uses it, one pair for each block that memexec numbered when it stored
   the entry, see [Mem_exec]. The empty list is the identity. *)
type renaming = (Base.t * Base.t) list

module Renaming = Datatype.List (Datatype.Pair (Base) (Base))

let equal_renaming = Renaming.equal

(* A call made by the body of the analysed call of a cache entry, at the call
   statement [site], to [callee]: [child] is the cache entry it used, computed
   or hit, if any; none for a call analysed by a specification or a builtin.
   [renaming] is the renaming through which it used [child], from the blocks
   of the analysed call of [child] to the blocks of the body: the identity
   if it computed [child]. [start] is its start state, projected on the
   blocks that the body had read or written before [site], on those that do
   not exist in the start state of the body (the blocks the body created),
   and on those that the call binds or removes (the formals and locals of
   [callee], and the blocks of the start state of the body that the start
   state of the call does not have). None if the footprint of the body is
   unknown. *)
type below = {
  site: Cil_types.stmt;
  callee: Cil_types.kernel_function;
  child: int option;
  renaming: renaming;
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
            child = None; renaming = []; start = None } ]
      let structural_descr =
        let module Child = Datatype.Option (Datatype.Int) in
        let module Start = Datatype.Option (Point) in
        Structural_descr.t_record
          [| Cil_datatype.Stmt.packed_descr; Kernel_function.packed_descr;
             Child.packed_descr; Renaming.packed_descr; Start.packed_descr |]
    end)

(* The points absent from the tables are unreachable. With an unknown
   footprint, no point is kept. A heap call that is refused keeps the full
   state at each point instead of an Inner part. *)
type inner_part =
  | Unknown
  | Known of { before: point Stmt_table.t; after: point Stmt_table.t }
  | Full of {
      before: Cvalue.Model.t Stmt_table.t;
      after: Cvalue.Model.t Stmt_table.t;
    }

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
   request from the entries of their callers. [heap] tells whether the
   analysed call is a heap call: its key group is then made of this call
   only. The body-entry states of the hits are grouped by the renaming
   through which each hit used the entry. [mentioned] are the allocated
   blocks that memexec numbered when it stored the entry, in the order of
   their numbers: the empty list if the entry mentions none; None until
   memexec stores it, and if it does not. *)
type entry = {
  heap: bool;
  inner: inner_part;
  below: below list;
  analysed: analysed;
  hit_starts: states;
  mutable hit_body_entries: (renaming * states) list;
  mutable mentioned: Base.t list option;
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
             { heap = false; inner = Unknown; below = [];
               analysed = List.hd Analysed.reprs;
               hit_starts = states; hit_body_entries = [ [], states ];
               mentioned = None })
          States.reprs
      let structural_descr =
        let inner_part =
          let module Full_states = Stmt_table.Make (Cvalue.Model) in
          Structural_descr.t_sum
            [| [| Points.packed_descr; Points.packed_descr |];
               [| Full_states.packed_descr; Full_states.packed_descr |] |]
        in
        let module Below_list = Datatype.List (Below) in
        let module Groups = Datatype.List (Datatype.Pair (Renaming) (States)) in
        let module Mentioned = Datatype.Option (Datatype.List (Base)) in
        Structural_descr.t_record
          [| Structural_descr.p_bool;
             Structural_descr.pack inner_part;
             Below_list.packed_descr;
             Analysed.packed_descr;
             States.packed_descr;
             Groups.packed_descr;
             Mentioned.packed_descr |]
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
    | Full { before; after } ->
      Full { before = Stmt_table.copy before; after = Stmt_table.copy after }
  in
  { heap = entry.heap; inner; below = entry.below; analysed = entry.analysed;
    hit_starts = copy_states entry.hit_starts;
    hit_body_entries =
      List.map
        (fun (renaming, states) -> renaming, copy_states states)
        entry.hit_body_entries;
    mentioned = entry.mentioned }

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

(* A heap effect received by a call, see [Heap_effects]: emitted in its body,
   at the point given if any, or passed by the call made at a statement of
   the body, with the effects this call received. Lists of effects are in
   the reverse order of emission. *)
type received =
  | Here of Cil_types.stmt option * Heap_effects.t
  | Through of Cil_types.stmt * Cil_types.kernel_function * received list

type effects = received list

(* How the analysis of a call ends, as far as the sweeps are concerned: not
   known yet, without returning, or returning with the blocks swept on every
   path of the body and on some path only. *)
type exit =
  | Unset
  | No_return
  | Exit of Heap_paths.sweeps

(* A call being analysed, in any mode: the calls made by its body so far, each
   with its call statement, its function, its start state, the cache entry it
   used and the renaming through which it used it; the cache entry this call
   uses, once known, and the renaming through which it uses it; the heap
   effects it
   received so far; the sweeps of the calls made by its body, merged over the
   evaluations of each call statement, except the last evaluation, kept apart
   with its statement until the next one ends, see [add_evaluation]; the
   sweeps of the automatic releases that follow no evaluation; the variables
   that a recursive call withdraws from the state and puts back at its end,
   per call statement of the body that makes it or makes a call nested in
   which it is made, and overall; how the call ends, set when its body has
   been analysed; for a builtin, the number of states it returns; whether
   it is refused: it calls, or a call nested in it calls, a builtin that
   reads every allocated block; and whether its entry, or the entry of a
   call nested in it, holds full states, see [storage]. *)
type frame = {
  mutable calls:
    (Cil_types.stmt * Cil_types.kernel_function * Cvalue.Model.t * int option
     * renaming) list;
  mutable used: int option;
  mutable renaming: renaming;
  mutable effects: effects;
  site_sweeps: Heap_paths.sweeps Stmt_table.t;
  mutable last: (Cil_types.stmt * Heap_paths.sweeps) option;
  released: Heap_paths.sweeps Stmt_table.t;
  withdrawn_at: Base.Hptset.t Stmt_table.t;
  mutable withdrawn: Base.Hptset.t;
  mutable exit: exit;
  mutable outputs: int option;
  mutable refused: bool;
  mutable full_below: bool;
}

(* The parts of the recording used only while the analysis runs. They are
   neither saved nor copied. *)
type running = {
  (* The calls being analysed, innermost first. *)
  mutable frames: frame list;
  mutable slot: slot;
  (* The number of calls being analysed that memexec would have reused if it
     stored the heap calls, see [lost_hit]. *)
  mutable lost: int;
  (* The heap effects, the exit and the variables withdrawn by recursive
     calls of the analysed call of each cache entry that memexec may store
     as a heap call, by number, for its hits, see [record_hit]. The table
     is created when the first entry is kept, see [stored_table]: an
     analysis without -eva-hit-log creates none. *)
  mutable stored: (effects * exit * Base.Hptset.t) Int_table.t option;
}

let new_running () =
  { frames = []; slot = Closed; lost = 0; stored = None }

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

(* The set of the blocks of a zone, memoised by the zone. The footprints of a
   statement are often the same zone from one call to the next, and
   [Base.Hptset.from_map] walks the zone and hash-conses each node of the set
   again at each call. The memo is a direct-mapped cache, with as many slots
   as the caches of the hash-consed maps (option -cache-size), keyed by the
   shape of the zone. Zones are hash-consed: two shapes with the same
   bindings are the same value, and the cache compares them by physical
   equality, as [Base.Hptshape.equal] does. The set is a function of the
   blocks bound in the shape, so a hit gives the set that [from_map] builds,
   itself hash-consed: the same value. The answer does not depend on the
   project, and the cache needs no clearing. A slot keeps its zone and its
   set alive until another zone takes it. *)
module Zone_bases =
  Binary_cache.Arity_One
    (struct
      type t = Int_Intervals.t Base.Hptshape.map
      let hash = Base.Hptshape.hash
      let equal = Base.Hptshape.equal
      (* The empty zone, whose set of blocks is the sentinel of the sets. *)
      let sentinel =
        match Memory_zone.bottom with
        | Memory_zone.Map map -> Memory_zone.shape map
        | Memory_zone.Top _ -> assert false
    end)
    (struct
      type t = Base.Hptset.t
      let sentinel = Base.Hptset.empty
    end)

let bases_of_zone = function
  | Memory_zone.Top (Base.SetLattice.Top, _) -> raise Unknown_footprint
  | Memory_zone.Top (Base.SetLattice.Set bases, _) -> bases
  | Memory_zone.Map map ->
    Zone_bases.merge Base.Hptset.from_map (Memory_zone.shape map)

(* The blocks that a state of the body of a call creates or removes, compared
   with the start state of the call, are computed by walking the two maps
   together: the subtrees present in one map only hold these blocks, and the
   keys present in both maps give none. The walk does not enter the subtrees
   shared by the two maps, and does not build the set of all blocks of a
   state. *)

type shape = Cvalue.V_Offsetmap.t Base.Hptshape.map

(* The shape of a state: [None] for Bottom, which has no blocks. *)
let shape_of_state = function
  | Cvalue.Model.Bottom -> None
  | Top -> raise Unknown_footprint
  | Map map -> Some (Cvalue.Model.shape map)

(* [created_in start state] are the blocks of [state] absent from [start]. *)
let created_in : shape -> shape -> Base.Hptset.t =
  let join s t =
    if Base.Hptset.is_empty s then t
    else if Base.Hptset.is_empty t then s
    else Base.Hptset.union s t
  in
  Base.Hptshape.fold2_join_homogeneous
    ~cache:Hptmap_sig.NoCache
    ~empty_left:Base.Hptset.from_map
    ~empty_right:(fun _ -> Base.Hptset.empty)
    ~both:(fun _ _ _ -> Base.Hptset.empty)
    ~same:(fun _ -> Base.Hptset.empty)
    ~join ~empty:Base.Hptset.empty

(* No block created or removed. Shared, so that the walk below allocates no
   pair where neither map has blocks of its own. *)
let no_change = Base.Hptset.empty, Base.Hptset.empty

(* [changes_in start state] are the blocks of [state] absent from [start],
   and those of [start] absent from [state]. *)
let changes_in : shape -> shape -> Base.Hptset.t * Base.Hptset.t =
  let join (created, removed as x) (created', removed' as y) =
    if x == no_change then y
    else if y == no_change then x
    else Base.Hptset.union created created', Base.Hptset.union removed removed'
  in
  Base.Hptshape.fold2_join_homogeneous
    ~cache:Hptmap_sig.NoCache
    ~empty_left:(fun t -> Base.Hptset.from_map t, Base.Hptset.empty)
    ~empty_right:(fun s -> Base.Hptset.empty, Base.Hptset.from_map s)
    ~both:(fun _ _ _ -> no_change)
    ~same:(fun _ -> no_change)
    ~join ~empty:no_change

(* The blocks of [state] absent from [start], the shape of the start state of
   the call. *)
let created_blocks ~start state =
  match start, shape_of_state state with
  | _, None -> Base.Hptset.empty
  | None, Some state -> Base.Hptset.from_map state
  | Some start, Some state -> created_in start state

(* The blocks of [state] absent from [start], the shape of the start state of
   the call, and the blocks of [start] absent from [state]. *)
let created_and_removed_blocks ~start state =
  match start, shape_of_state state with
  | None, None -> no_change
  | None, Some state -> Base.Hptset.from_map state, Base.Hptset.empty
  | Some start, None -> Base.Hptset.empty, Base.Hptset.from_map start
  | Some start, Some state -> changes_in start state

(* Projects [state] on the blocks of [zone], on the blocks [created] that do
   not exist in the start state of the call, and on [bound], with the sweep
   map [sweeps]. *)
let project ?(bound = Base.Hptset.empty) ?(sweeps = Heap_paths.no_sweep)
    ~created zone state =
  let covered = Base.Hptset.union (bases_of_zone zone) created in
  let covered = Base.Hptset.union covered bound in
  { covered; inner = Cvalue.Model.filter_by_shape covered state;
    swept_every = sweeps.every; swept_some = sweeps.some }

(* The blocks that a call to [callee] binds or removes: the formals of
   [callee], bound by the call; its locals, absent from its start state; and
   [removed], the blocks of the start state of the body that makes the call
   that are absent from the start state of the call. With unrolled recursive
   calls, the formals and locals of [callee] can exist in the state of the
   caller, in the frame of an outer call of [callee]: a recursive call removes
   them, or renames those whose address is taken, and binds the formals
   anew. *)
let bound_by_call ~removed callee =
  let vars = Kernel_function.(get_formals callee @ get_locals callee) in
  let vars = Base.Hptset.of_list (List.map Base.of_varinfo vars) in
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
   successors.
   For a heap call, [heap_before] and [heap_after] give at each point, from
   the state there, the blocks that its heap effects cover, which are covered
   as well, and the sweep map. The start state of a call made by the body is
   projected with the coverage and the sweep map before its call statement,
   from this start state. *)
let no_heap _ _ = Heap_paths.empty

let inner_part ?(heap_before = no_heap) ?(heap_after = no_heap) footprint
    ~start ~before ~after ~calls =
  let start = shape_of_state start in
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
  let project_all zone_of heap_of states =
    let points = Stmt_table.create (Stmt_table.length states) in
    let add stmt state =
      let created = created_blocks ~start state in
      let { Heap_paths.covered; sweeps } = heap_of stmt state in
      Stmt_table.replace points stmt
        (project ~bound:covered ~sweeps ~created (zone_of stmt) state)
    in
    Stmt_table.iter add states;
    points
  in
  let before = project_all zone_before heap_before (Lazy.force before) in
  let after = project_all zone_after heap_after (Lazy.force after) in
  let below =
    List.rev_map
      (fun (site, callee, state, child, renaming) ->
         let created, removed = created_and_removed_blocks ~start state in
         let bound = bound_by_call ~removed callee in
         let { Heap_paths.covered; sweeps } = heap_before site state in
         let bound = Base.Hptset.union bound covered in
         let start = project ~bound ~sweeps ~created (zone_before site) state in
         { site; callee; child; renaming; start = Some start })
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

(* A heap call is a call analysed by its body that receives a heap effect,
   see [receive]. [call] passes the effects of a frame to the frame of its
   caller when the call ends, up to the entry point. The analysis of a body
   ends after the analyses of the calls it makes, and after the automatic
   release at the end of each of them: the effects of a call analysed by its
   body are final when [record_analysed_call] records it, and when memexec
   decides whether to store the call. A hit on the entry of a heap call
   receives the effects of the analysed call of the entry, through its
   renaming, see [record_hit]. The specifications neither allocate nor
   release memory in the cvalue domain. *)

let heap_calls = Statistics.(register_function_stat "hit-log-heap-calls" Int)
let full_states = Statistics.(register_function_stat "hit-log-full-states" Int)
let lost_hits = Statistics.(register_function_stat "hit-log-lost-hits" Int)
let lost_hits_below =
  Statistics.(register_function_stat "hit-log-lost-hits-below" Int)

(* Merges the last evaluation of a call made by the body of [frame] into the
   evaluations of its statement before it. *)
let flush_evaluation frame =
  match frame.last with
  | None -> ()
  | Some (site, sweeps) ->
    frame.last <- None;
    let sweeps =
      match Stmt_table.find_opt frame.site_sweeps site with
      | None -> sweeps
      | Some previous -> Heap_paths.merge previous sweeps
    in
    Stmt_table.replace frame.site_sweeps site sweeps

(* The automatic release at the end of a call sweeps [block] in each state
   that the call returns, after the frame of the call is closed and before
   another call starts: its sweep follows those of the evaluation of the
   call, the last one of [frame], before it is merged with the other
   evaluations of [stmt]. A sweep that follows no evaluation of [stmt] is
   kept on some path only. *)
let release frame stmt ~exact block =
  let sweep = Heap_paths.sweep ~exact block in
  match frame.last with
  | Some (site, sweeps) when Cil_datatype.Stmt.equal site stmt ->
    frame.last <- Some (site, Heap_paths.sequence sweeps sweep)
  | Some _ | None ->
    let previous =
      Option.value ~default:Heap_paths.no_sweep
        (Stmt_table.find_opt frame.released stmt)
    in
    Stmt_table.replace frame.released stmt
      (Heap_paths.sequence previous (Heap_paths.weaken sweep))

(* A heap effect goes to the innermost frame: the call of the builtin that
   emits it, the call whose body is widened, or the call in whose body a call
   ends, for the automatic release at the end of that call, which is the
   only effect emitted with the statement of a call. [call] passes the
   effects of a frame to the frame of its caller when the call ends. *)
let receive ?point e =
  if enabled () then
    match (Running.get ()).frames with
    | frame :: _ ->
      frame.effects <- Here (point, e) :: frame.effects;
      begin match point, e with
        | Some stmt, Heap_effects.Sweep { block; exact } ->
          release frame stmt ~exact block
        | Some _, (Allocation _ | Mutation _ | Removal _) | None, _ -> ()
      end
    | [] -> ()

let () = Heap_effects.register_sink receive

(* A builtin that reads every allocated block refuses the innermost frame,
   its own; [call] passes the refusal to the frame of its caller. *)
let () =
  Heap_effects.register_whole_heap_reader
    (fun () ->
       if enabled () then
         Option.iter (fun frame -> frame.refused <- true) (current_frame ()))

let builtin_outputs n =
  Option.iter (fun frame -> frame.outputs <- Some n) (current_frame ())

let effects_hooks = ref []

let register_effects_hook f = effects_hooks := !effects_hooks @ [ f ]

let iter_effects f effects =
  let rec through site kf received =
    List.iter
      (function
        | Here (_, e) -> f (Some site) (Some kf) e
        | Through (_, _, received) -> through site kf received)
      (List.rev received)
  in
  List.iter
    (function
      | Here (point, e) -> f point None e
      | Through (site, kf, received) -> through site kf received)
    (List.rev effects)

(* A call that memexec would have reused if it stored the heap calls is
   counted in [lost_hits], unless it is made during the analysis of such a
   call: it would then have been below a hit, and is counted in
   [lost_hits_below]. *)
let lost_hit kf f =
  let running = Running.get () in
  let stat = if running.lost = 0 then lost_hits else lost_hits_below in
  Statistics.incr stat kf;
  running.lost <- running.lost + 1;
  Fun.protect ~finally:(fun () -> running.lost <- running.lost - 1) f

(* A call that is not a heap call makes no heap call: [call] passes the
   effects of a heap call to its caller, those of a hit on the entry of a
   heap call included, see [record_hit]. Checked on the calls made by the
   body of any other call that used a cache entry. *)
let check_no_heap_child store calls =
  List.iter
    (fun (_, callee, _, child, _) ->
       let entry = Option.map (Int_table.find_opt store.entries) child in
       match entry with
       | Some (Some { heap = true; _ }) ->
         Self.fatal
           "hit log: call to %a, a heap call, made by a call that is not one"
           Kernel_function.pretty callee
       | Some (Some { heap = false; _ } | None) | None -> ())
    calls

(* ----- Heap calls: coverage and sweep map -------------------------------- *)

(* The sweeps of the analysis of a call that ended, from its start to its
   return; None if it does not return. They are set when the body of a call
   analysed by its body is recorded. Those of a builtin are its own sweeps,
   in the order of emission, on some path only if it returns several states:
   [realloc] releases the block in the state of its success only. Any other
   call receives no sweep, unless its analysis was interrupted: its sweeps
   are then on some path only. *)
let evaluation_sweeps frame =
  match frame.exit, frame.outputs with
  | Exit sweeps, _ -> Some sweeps
  | No_return, _ | Unset, Some 0 -> None
  | Unset, outputs ->
    let rec add acc = function
      | Here (_, Heap_effects.Sweep { block; exact }) ->
        Heap_paths.(sequence acc (sweep ~exact block))
      | Here (_, (Allocation _ | Mutation _ | Removal _)) -> acc
      | Through (_, _, received) -> List.fold_left add acc (List.rev received)
    in
    let sweeps =
      List.fold_left add Heap_paths.no_sweep (List.rev frame.effects)
    in
    match outputs with
    | Some 1 -> Some sweeps
    | Some _ | None -> Some (Heap_paths.weaken sweeps)

(* Keeps the sweeps of the call of [frame], made at [site], as the last
   evaluation of the frame [caller], which the automatic release at the end
   of the call follows, see [release]; the previous last evaluation is
   merged. A call that does not return is left out: no state follows it,
   and no release. *)
let add_evaluation caller site frame =
  flush_evaluation caller;
  match evaluation_sweeps frame with
  | None -> ()
  | Some sweeps -> caller.last <- Some (site, sweeps)

(* Adds [withdrawn], the variables that a recursive call made at [site] or
   nested in the call made there withdraws and puts back, to those of the
   frame [caller]. *)
let add_withdrawn caller site withdrawn =
  if not (Base.Hptset.is_empty withdrawn) then begin
    let previous =
      Option.value ~default:Base.Hptset.empty
        (Stmt_table.find_opt caller.withdrawn_at site)
    in
    Stmt_table.replace caller.withdrawn_at site
      (Base.Hptset.union previous withdrawn);
    caller.withdrawn <- Base.Hptset.union caller.withdrawn withdrawn
  end

(* A recursive call puts back the variables that it withdraws as they were
   before the call: the releases made by the call do not sweep them, while
   the sweep map of the calls in which it is nested would. These calls
   cover the variables after their call statement that leads to it, so that
   the rule takes them from the Inner part. The frame of the call that makes
   the recursive call is the innermost one, as the frame of the recursive
   call is not created yet. *)
let recursive_call callstack (recursion: Eval.recursion) =
  if enabled () then
    match current_frame (), Callstack.top_callsite callstack with
    | Some frame, Kstmt site ->
      add_withdrawn frame site recursion.base_withdrawal
    | Some _, Kglobal | None, _ -> ()

(* The blocks that the heap effects of [received] allocate, mutate or
   remove, added to [acc]. *)
let rec add_effect_blocks acc = function
  | Here (_, (Heap_effects.Allocation { block; _ }
             | Mutation { block; _ } | Removal block)) ->
    Base.Hptset.add block acc
  | Here (_, Sweep _) -> acc
  | Through (_, _, received) -> List.fold_left add_effect_blocks acc received

let is_call_statement (stmt: Cil_types.stmt) =
  match stmt.skind with
  | Instr (Call _ | Local_init (_, ConsInit _, _)) -> true
  | _ -> false

(* Whether the heap call of [frame] keeps full states: in threaded mode, when
   it or a call nested in it calls a builtin that reads every allocated
   block, or when it receives in its body an effect whose statement is not
   known. *)
let refused frame =
  frame.refused
  || Mt_options.Enabled.get ()
  || List.exists
    (function Here (None, _) -> true | Here (Some _, _) | Through _ -> false)
    frame.effects

(* The coverage and the sweep map of the heap call of [frame] at each vertex
   of [automaton], the automaton of its body, on the paths of the edges
   [fired], see [Heap_paths.compute]. The effects at a call statement act on
   the edge of the call: the blocks that the effects received by the call,
   and those of the automatic release at its end, allocate, mutate or remove
   are covered after it, and so are the variables that a recursive call
   nested there withdraws, see [recursive_call]; its sweeps are those of its
   evaluations, each followed by the automatic release at its end, merged,
   see [release]. The effects at another statement, the loop whose widening
   raises the validity of a block, act on entry to the vertex before this
   statement. *)
let heap_paths frame automaton ~fired =
  flush_evaluation frame;
  let covered = Stmt_table.create 7 in
  let update table stmt ~default f =
    let previous = Option.value ~default (Stmt_table.find_opt table stmt) in
    Stmt_table.replace table stmt (f previous)
  in
  let cover stmt received =
    update covered stmt ~default:Base.Hptset.empty
      (fun acc -> add_effect_blocks acc received)
  in
  List.iter
    (function
      | Through (site, _, _) as received -> cover site received
      | Here (None, _) | Here (Some _, Sweep _) -> ()
      | Here (Some stmt, _) as received -> cover stmt received)
    frame.effects;
  let find table stmt ~default =
    Option.value ~default (Stmt_table.find_opt table stmt)
  in
  let value stmt =
    let covered = find covered stmt ~default:Base.Hptset.empty in
    let withdrawn = find frame.withdrawn_at stmt ~default:Base.Hptset.empty in
    let covered = Base.Hptset.union covered withdrawn in
    let evaluations =
      find frame.site_sweeps stmt ~default:Heap_paths.no_sweep
    in
    let released = find frame.released stmt ~default:Heap_paths.no_sweep in
    { Heap_paths.covered; sweeps = Heap_paths.sequence evaluations released }
  in
  let at_vertex = Eva_automata.Vertex.Hashtbl.create 7 in
  let add_vertex stmt _ =
    if not (is_call_statement stmt) then
      match Stmt_table.find_opt automaton.Eva_automata.stmt_table stmt with
      | None -> ()
      | Some (vertex, _) ->
        let previous =
          Option.value ~default:Heap_paths.empty
            (Eva_automata.Vertex.Hashtbl.find_opt at_vertex vertex)
        in
        Eva_automata.Vertex.Hashtbl.replace at_vertex vertex
          (Heap_paths.after previous (value stmt))
  in
  Stmt_table.iter add_vertex covered;
  Stmt_table.iter add_vertex frame.released;
  let edge (e: Eva_automata.edge) =
    match e.edge_transition with
    | Call (_, _, _, stmt) -> value stmt
    | Skip | Enter _ | Leave _ | Return _ | Guard _ | Assign _ | Init _
    | Asm _ -> Heap_paths.empty
  in
  let vertex v =
    Option.value ~default:Heap_paths.empty
      (Eva_automata.Vertex.Hashtbl.find_opt at_vertex v)
  in
  Heap_paths.compute automaton ~fired ~edge ~vertex

let present state block =
  match state with
  | Cvalue.Model.Top -> true
  | Bottom -> false
  | Map _ ->
    match Cvalue.Model.find_base block state with
    | _ -> true
    | exception Not_found -> false

(* The sweeps [sweeps] at a point where the state is [state], in a call whose
   body-entry state is [body_entry]: a block swept on some path only that
   [body_entry] binds and [state] does not is swept on every path. The
   preconditions only reduce the start state: every body-entry state binds
   the blocks of their join. A block that no state at the point binds was
   thus removed on every path that reaches it, by a release that removes
   the block and sweeps the pointers to it in the same step. The join of
   memory states binds every block that one of them binds. A recursive call
   puts back the variables that it withdraws unswept, but these are covered
   after the call, see [recursive_call]. *)
let promote ~body_entry state sweeps =
  Heap_paths.promote
    (fun block -> present body_entry block && not (present state block))
    sweeps

(* The coverage and the sweep map before and after each statement of the
   body, from their values at the vertices of [automaton], as the legacy
   store computes the states before and after each statement from the
   states at the vertices: the state after a statement that is not an
   instruction is the join of the states before its successors reached, as
   given by [before], and the state after the return statement is the state
   before it. The sweep map keeps every block swept, including those that
   the body-entry state does not bind: this state can hold pointers to such
   a block, as a recursive call puts back unswept the variables it withdraws
   from the state, and a release of the block in the body sweeps them. The
   sweeps at a point are promoted from the state there, see [promote].
   Raises [Unknown_footprint] at a point whose vertex the paths do not
   reach. *)
let heap_points automaton paths ~body_entry ~before =
  let at vertex =
    match Eva_automata.Vertex.Hashtbl.find_opt paths vertex with
    | Some value -> value
    | None -> raise Unknown_footprint
  in
  let vertices stmt =
    match Stmt_table.find_opt automaton.Eva_automata.stmt_table stmt with
    | Some vertices -> vertices
    | None -> raise Unknown_footprint
  in
  let path_before stmt = at (fst (vertices stmt)) in
  let path_after (stmt: Cil_types.stmt) =
    match stmt.skind with
    | Instr _ -> at (snd (vertices stmt))
    | Return _ -> path_before stmt
    | _ ->
      let before = Lazy.force before in
      List.filter (Stmt_table.mem before) stmt.succs
      |> List.map path_before
      |> function
      | [] -> raise Unknown_footprint
      | value :: values -> List.fold_left Heap_paths.join value values
  in
  let promoted path stmt state =
    let value = path stmt in
    { value with
      Heap_paths.sweeps = promote ~body_entry state value.Heap_paths.sweeps }
  in
  promoted path_before, promoted path_after

(* The sweeps of the heap call that [paths] gives at the return point of
   [automaton], promoted from the state before the return statement of [kf],
   see [promote]; [No_return] if the paths do not reach this point. *)
let exit_sweeps kf automaton paths ~body_entry ~before =
  match
    Eva_automata.Vertex.Hashtbl.find_opt paths
      automaton.Eva_automata.return_point
  with
  | None -> No_return
  | Some value ->
    let state =
      match Kernel_function.find_return kf with
      | stmt -> Stmt_table.find_opt (Lazy.force before) stmt
      | exception Kernel_function.No_Statement -> None
    in
    match state with
    | None -> Exit value.Heap_paths.sweeps
    | Some state -> Exit (promote ~body_entry state value.Heap_paths.sweeps)

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

let record_analysed_call ~id callstack ~automaton ~fired ~footprint ~start
    ~body_entry ~before ~after =
  let store = Store.get () in
  let kf = Callstack.top_kf callstack in
  let frame = current_frame () in
  let calls =
    match frame with
    | None -> []
    | Some frame -> frame.used <- Some id; frame.calls
  in
  let heap =
    Option.fold ~none:false ~some:(fun frame -> frame.effects <> []) frame
  in
  let unknown () =
    let below =
      List.rev_map
        (fun (site, callee, _, child, renaming) ->
           { site; callee; child; renaming; start = None })
        calls
    in
    Unknown, below
  in
  (* An entry that holds full states is never stored by memexec: it keeps
     no call made by its body. *)
  let full () =
    if heap then Statistics.incr full_states kf;
    Full { before = Lazy.force before; after = Lazy.force after }, []
  in
  (* The sweeps of a heap call are computed for its caller, even when it
     keeps full states. *)
  let inner, below =
    match frame with
    | Some frame when heap ->
      Statistics.incr heap_calls kf;
      let paths = heap_paths frame automaton ~fired in
      frame.exit <- exit_sweeps kf automaton paths ~body_entry ~before;
      begin match footprint with
        | None -> Unknown, []
        | Some _ when refused frame -> full ()
        | Some footprint ->
          try
            let heap_before, heap_after =
              heap_points automaton paths ~body_entry ~before
            in
            inner_part ~heap_before ~heap_after footprint ~start ~before
              ~after ~calls
          with Unknown_footprint -> full ()
      end
    | Some _ | None ->
      Option.iter (fun frame -> frame.exit <- Exit Heap_paths.no_sweep) frame;
      match footprint with
      | None -> check_no_heap_child store calls; unknown ()
      | Some footprint ->
        check_no_heap_child store calls;
        try inner_part footprint ~start ~before ~after ~calls
        with Unknown_footprint -> unknown ()
  in
  if inner = Unknown then mark store.body_unavailable kf;
  begin match inner, frame with
    | Full _, Some frame -> frame.full_below <- true
    | (Unknown | Known _ | Full _), _ -> ()
  end;
  let entry = {
    heap;
    inner;
    below;
    analysed = { callstack; start; body_entry };
    hit_starts = new_states ();
    hit_body_entries = [];
    mentioned = None;
  } in
  Int_table.replace store.entries id entry;
  let previous =
    Option.value ~default:[] (Kf_table.find_opt store.entries_of kf)
  in
  Kf_table.replace store.entries_of kf (id :: previous)

(* The states of [groups] for [renaming], added to [groups] if absent. *)
let group_states entry renaming =
  match
    List.find_opt
      (fun (r, _) -> equal_renaming r renaming) entry.hit_body_entries
  with
  | Some (_, states) -> states
  | None ->
    let states = new_states () in
    entry.hit_body_entries <- entry.hit_body_entries @ [ renaming, states ];
    states

(* The entry computed by the call being analysed is the one its frame used,
   as set by [record_analysed_call]: memexec stores it once its body has been
   analysed, within this frame. *)
let record_mentioned mentioned =
  match current_frame (), mentioned with
  | Some { used = Some id; _ }, Some _ ->
    Option.iter
      (fun entry -> entry.mentioned <- mentioned)
      (Int_table.find_opt (Store.get ()).entries id)
  | _ -> ()

(* The image of a heap effect [e] of the analysed call of an entry, by
   [rename] on its blocks, [size] on the size of an allocation and [stack] on
   the stack of an allocation. *)
let rename_effect ~rename ~size ~stack (e: Heap_effects.t) : Heap_effects.t =
  match e with
  | Allocation a ->
    Allocation
      { a with block = rename a.block; size = size a.size;
               stack = stack a.stack }
  | Mutation m -> Mutation { m with block = rename m.block }
  | Removal block -> Removal (rename block)
  | Sweep s -> Sweep { s with block = rename s.block }

let rec rename_received f = function
  | Here (point, e) -> Here (point, f e)
  | Through (site, kf, received) ->
    Through (site, kf, List.map (rename_received f) received)

(* The image of [sweeps] by [rename]: a block swept on every path has its
   image swept on every path, and so on. *)
let rename_sweeps rename (sweeps: Heap_paths.sweeps) =
  let add ~exact block acc =
    Heap_paths.sequence acc (Heap_paths.sweep ~exact (rename block))
  in
  Base.Hptset.fold (add ~exact:true) sweeps.every
    (Base.Hptset.fold (add ~exact:false) sweeps.some Heap_paths.no_sweep)

(* The hit on [callstack] of the entry [id] of a heap call, [entry], through
   [renaming], receives in [frame] the heap effects of the analysed call of
   the entry, in their order, its exit, and the variables that the
   recursive calls nested in it withdrew, which are not allocated blocks,
   see [recursive_call]. The blocks of the effects and of
   the exit are renamed through [renaming], and so are the pointers that the
   size of an allocation may hold. The statements of the effects are those
   of the body of the same function. The stack of an allocation is the
   callstack of the hit extended by the calls of the stack of the analysed
   call below its callstack: the policy [by_stack] made the blocks of the
   replay on these stacks, see [Mem_exec]. Every block that the effects
   name is a block that memexec numbered in the entry, or a block that the
   analysed call created: the renaming, if not the identity, maps each of
   them. *)
let receive_entry_effects ~id ~renaming callstack entry frame =
  let kept =
    match (Running.get ()).stored with
    | Some table -> Int_table.find_opt table id
    | None -> None
  in
  match kept with
  | None ->
    Self.fatal "hit log: hit of the cache entry %d of a heap call, whose \
                effects were not kept" id
  | Some (effects, exit, withdrawn) ->
    let rename block =
      match renaming with
      | [] -> block
      | _ ->
        match List.find_opt (fun (b, _) -> Base.equal b block) renaming with
        | Some (_, image) -> image
        | None ->
          Self.fatal "hit log: block %a of the cache entry %d not renamed by \
                      a hit" Base.pretty block id
    in
    let size =
      match renaming with
      | [] -> Fun.id
      | _ ->
        let substitution = Base.substitution_from_list renaming in
        fun v -> snd (Cvalue.V.replace_base substitution v)
    in
    let stack s =
      match Mem_exec.suffix_below ~callstack:entry.analysed.callstack s with
      | Some suffix -> Mem_exec.extend callstack suffix
      | None ->
        Self.fatal "hit log: allocation of the cache entry %d not below its \
                    analysed call" id
    in
    let f = rename_effect ~rename ~size ~stack in
    frame.effects <- List.map (rename_received f) effects @ frame.effects;
    frame.withdrawn <- Base.Hptset.union frame.withdrawn withdrawn;
    frame.exit <-
      match exit with
      | Exit sweeps -> Exit (rename_sweeps rename sweeps)
      | No_return | Unset -> exit

(* A hit on the entry of a heap call passes the heap effects of the entry
   to the call that makes it, through its renaming, as the analysed call of
   the entry did, see [receive_entry_effects]: [call] passes them to the
   caller. *)
let record_hit ~id ~renaming callstack ~start ~body_entry =
  let store = Store.get () in
  let frame = current_frame () in
  Option.iter
    (fun frame -> frame.used <- Some id; frame.renaming <- renaming)
    frame;
  match Int_table.find_opt store.entries id with
  | None -> store.unrecorded_hit <- true
  | Some { inner = Full _; _ } ->
    Self.fatal "hit log: hit of the cache entry %d, which holds full states"
      id
  | Some entry ->
    if entry.heap then
      Option.iter (receive_entry_effects ~id ~renaming callstack entry) frame;
    add_state entry.hit_starts callstack start;
    add_state (group_states entry renaming) callstack body_entry

type storage =
  | Plain
  | Heap of Mem_exec.heap
  | Refused

(* The heap effects [effects] of a call on [callstack] that memexec can
   store: the blocks they remove and sweep, their validity mutations in the
   order of emission, and their allocations, in the order of emission.
   Among the allocation builtins, the builtin of [malloc] under the policy
   [by_stack], at a site without annotation, lets memexec store its callers;
   so do the builtins of the policy [imprecise] once their single block
   exists, whose allocations this function refuses. [None] if an effect
   refuses the call:
   - an allocation by another policy than [by_stack], of a block that is not
     a heap allocation, or whose stack, without the allocation wrappers,
     ends at or above the call: the call is then an allocation wrapper, or
     made by one;
   - a validity mutation that is not the resize of the block that the
     allocation emitted just before it reuses, as the widening of a weak
     block in a loop. *)
let heap_effects_of ~callstack effects =
  let removed = ref Base.Hptset.empty and swept = ref Base.Hptset.empty in
  let mutations = ref [] and allocations = ref [] in
  let last = ref None in
  let rec add = function
    | Here (point, e) -> add_effect point e
    | Through (_, _, received) -> List.iter add (List.rev received)
  and add_effect point e =
    begin match point, e with
      | _, Heap_effects.Removal block ->
        removed := Base.Hptset.add block !removed
      | _, Sweep { block; _ } -> swept := Base.Hptset.add block !swept
      | None, Mutation { block; _ } ->
        mutations := e :: !mutations;
        begin match !last with
          | Some (Heap_effects.Allocation { block = b; decision = Reused _; _ })
            when Base.equal b block -> ()
          | Some _ | None -> raise Exit
        end
      | Some _, Mutation _ -> raise Exit
      | _, Allocation { block; policy; stack; rank; size; decision; _ } ->
        let suffix = Mem_exec.suffix_below ~callstack stack in
        match policy, block, rank, suffix with
        | Eva_annotations.By_stack, Base.Allocated (_, Base.Malloc, _),
          Some rank, Some suffix ->
          allocations :=
            { Mem_exec.block; suffix; rank; size; decision } :: !allocations
        | _ -> raise Exit
    end;
    last := Some e
  in
  match List.iter add (List.rev effects) with
  | exception Exit -> None
  | () ->
    Some (!removed, !swept, List.rev !mutations, List.rev !allocations)

(* For the allocations [allocations] of a call on [callstack], in their
   order: the stacks on which they allocate, by the order of the first
   allocation on each, each with its candidates, the blocks that the policy
   [by_stack] made on it before the call; and the blocks they create, in the
   order of their creation. The policy adds each block it creates at the
   end of the list of its stack, and only a call of [malloc] on this stack,
   made in the call, adds to this list: the candidates are the list now
   without the blocks created by the call, which are its last blocks. [None]
   if they are not. *)
let candidates_and_created ~callstack allocations =
  let created =
    List.filter_map
      (fun (a: Mem_exec.allocation) ->
         match a.decision with
         | Created -> Some a.block
         | Reused _ -> None)
      allocations
  in
  let same suffix (a: Mem_exec.allocation) =
    List.equal Callstack.Call.equal suffix a.suffix
  in
  let suffixes =
    List.fold_left
      (fun acc (a: Mem_exec.allocation) ->
         if List.exists (fun s -> same s a) acc then acc
         else acc @ [ a.suffix ])
      [] allocations
  in
  let candidates suffix =
    let on_stack =
      Builtins_malloc.malloced_on (Mem_exec.extend callstack suffix)
    in
    let created_here =
      List.filter_map
        (fun (a: Mem_exec.allocation) ->
           match a.decision with
           | Created when same suffix a -> Some a.block
           | Created | Reused _ -> None)
        allocations
    in
    let before = List.length on_stack - List.length created_here in
    let rec split n list =
      if n = 0 then Some ([], list)
      else
        match list with
        | [] -> None
        | b :: rest ->
          Option.map (fun (l, r) -> b :: l, r) (split (n - 1) rest)
    in
    match split before on_stack with
    | Some (candidates, rest) when List.equal Base.equal rest created_here ->
      Some (suffix, candidates)
    | Some _ | None -> None
  in
  let candidates = List.map candidates suffixes in
  if List.for_all Option.is_some candidates
  then Some (List.filter_map Fun.id candidates, created)
  else None

(* The table of the entries kept for their hits, created at its first
   use. *)
let stored_table () =
  let running = Running.get () in
  match running.stored with
  | Some table -> table
  | None ->
    let table = Int_table.create 7 in
    running.stored <- Some table;
    table

(* A heap call that is not refused, whose entry holds an Inner part, and
   whose effects memexec can store, see [heap_effects_of], is stored by
   memexec, with its sweeps from the start of its body to its return and
   its allocations. Its effects, its exit and the variables withdrawn by
   the recursive calls nested in it are kept for its hits, see
   [record_hit]. The sweeps of the automatic release at the end of the
   call go to its caller. A call whose entry, or the entry of a call nested
   in it, holds full states is not stored: the full states of an entry
   answer the requests on the callstack of its analysed call only, and a
   call nested in a hit would have none. A heap call can keep full states
   while the heap call that makes it does not, as when its footprint is
   unknown at one of its points only. *)
let storage ~callstack =
  match current_frame () with
  | None -> Plain
  | Some frame when frame.full_below -> Refused
  | Some { effects = []; _ } -> Plain
  | Some frame ->
    let known =
      match Option.map (Int_table.find_opt (Store.get ()).entries) frame.used
      with
      | Some (Some { inner = Known _; _ }) -> true
      | Some (Some { inner = Unknown | Full _; _ } | None) | None -> false
    in
    if refused frame || not known then Refused
    else
      match heap_effects_of ~callstack frame.effects with
      | None -> Refused
      | Some (removed, swept, mutations, allocations) ->
        match candidates_and_created ~callstack allocations with
        | None -> Refused
        | Some (candidates, created) ->
          let exit =
            match frame.exit with
            | Exit sweeps -> sweeps
            | No_return | Unset -> Heap_paths.no_sweep
          in
          Option.iter
            (fun id ->
               Int_table.replace (stored_table ()) id
                 (frame.effects, frame.exit, frame.withdrawn))
            frame.used;
          Heap { Mem_exec.removed; swept; exit; mutations; allocations;
                 candidates; created }

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
  let frame = {
    calls = []; used = None; renaming = []; effects = [];
    site_sweeps = Stmt_table.create 1; last = None;
    released = Stmt_table.create 1; withdrawn_at = Stmt_table.create 1;
    withdrawn = Base.Hptset.empty; exit = Unset; outputs = None;
    refused = false; full_below = false;
  } in
  running.frames <- frame :: running.frames;
  let finally () =
    running.frames <- List.tl running.frames;
    List.iter (fun f -> f callstack frame.effects) !effects_hooks;
    match running.frames, Callstack.top_callsite callstack with
    | caller :: _, Kstmt site ->
      let kf = Callstack.top_kf callstack in
      if frame.effects <> [] then
        caller.effects <- Through (site, kf, frame.effects) :: caller.effects;
      if frame.refused then caller.refused <- true;
      if frame.full_below then caller.full_below <- true;
      add_withdrawn caller site frame.withdrawn;
      add_evaluation caller site frame;
      let call = site, kf, start, frame.used, frame.renaming in
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
   recursion ends.

   A call below a hit crosses a recursion when it is a recursive call that
   renames variables, its function being already on the callstack of its
   caller, or when it is made below such a call. A recursive call renames
   the variables of the outer call of its function whose address is taken or
   that an argument of the call copies, and rewrites the pointers to them in
   the whole state, according to its depth on the callstack, whether it is
   analysed by its body or by its specification. It removes the other
   variables of the outer call, as the stored start state does, but the
   stored start state does not replay the renaming on the blocks it does not
   cover. The state of a call that crosses a recursion is thus top, on its
   callstack and in the joined states that include it, unless the call is
   unreachable. The points of its body, if it has one, pasted on this state,
   are top as well.

   Each member whose body did not run uses its entry through a renaming,
   from the blocks of the analysed call of the entry to its own blocks: a
   hit, through the renaming that memexec gives; a call below a member of
   [parent] that used the entry through the renaming rho, as recorded in
   [parent], through the composition of the renaming sigma of that member
   with rho. Its start state is the stored start state renamed by sigma,
   pasted on the body-entry state of the member of [parent]. The members
   are grouped by renaming, and per callstack by renaming: a state at a
   point of the body of the entry is pasted once per group, from the point
   of the Inner part renamed through the renaming of the group, and the
   states of the groups are joined. *)

(* The states of the members of an entry, grouped by renaming. *)
type groups = (renaming * Cvalue.Model.t) list

(* Joins [state] into the group of [renaming] in [groups]. *)
let add_group renaming state groups =
  let rec add = function
    | [] -> [ renaming, state ]
    | (r, previous) :: rest when equal_renaming r renaming ->
      (r, Cvalue.Model.join previous state) :: rest
    | group :: rest -> group :: add rest
  in
  add groups

let join_groups groups =
  List.fold_left
    (fun acc (_, state) -> Cvalue.Model.join acc state)
    Cvalue.Model.bottom groups

(* The renaming of the call [below] made by a member that uses the entry of
   its caller through [sigma], [below] having used its own entry through
   [rho]. [sigma], if not the identity, has a pair for each block that
   memexec numbered in the entry of the caller, the blocks that the caller
   created included; so has [rho] for the entry of the callee. The images
   by [rho] are blocks of the analysed call of the caller that its entry
   numbers: the key of the caller holds the key of the callee, renamed
   through [rho] by the inout plugin, so that every allocated block that
   the callee mentions is mentioned by the caller, and the caller receives
   the heap effects of the entry of the callee through [rho], see
   [record_hit], so that a block that the callee created is a block that
   the caller created. If [rho] is the identity, the callee mentions
   blocks of the analysed call of the caller, and [sigma] renames them: the
   result is [sigma] restricted to the blocks that the entry of the callee
   mentions, the identity if it mentions none. A block of this entry that
   [sigma] does not rename gets no pair, so that [rename] refuses the points
   that hold it. If memexec did not store the entry of the callee, its
   blocks are not known, and the result is [sigma]. *)
let compose store sigma (below: below) =
  let rho = below.renaming in
  match sigma, rho with
  | [], _ -> rho
  | _, [] ->
    let child = Option.map (Int_table.find_opt store.entries) below.child in
    begin match child with
      | None | Some None | Some (Some { mentioned = None; _ }) -> sigma
      | Some (Some { mentioned = Some blocks; _ }) ->
        let restricted =
          List.filter (fun (b, _) -> List.exists (Base.equal b) blocks) sigma
        in
        if List.for_all (fun (b, image) -> Base.equal b image) restricted
        then []
        else restricted
    end
  | _ ->
    let image block =
      match List.find_opt (fun (b, _) -> Base.equal b block) sigma with
      | Some (_, image) -> image
      | None -> block
    in
    let composed = List.map (fun (b, block) -> b, image block) rho in
    if List.for_all (fun (b, image) -> Base.equal b image) composed then []
    else composed

type derived = {
  (* The calls stored in the entries, with the number of the entry that
     stores them, by the entry they used. *)
  by_child: (int * below) list Int_table.t;
  (* The same calls, by the function they call. *)
  by_callee: (int * below) list Kf_table.t;
  (* For each entry, the body-entry states of its members whose body did not
     run, joined, and per callstack, grouped by renaming. *)
  unrun_joined: groups Int_table.t;
  unrun_by_callstack: groups Cs_table.t Int_table.t;
  (* For each entry, the functions on the callstacks of these members, and
     whether one of these callstacks may cross a recursion. *)
  unrun_frames: (Kernel_function.Set.t * bool) Int_table.t;
  (* For each function, the start states of the calls below a hit, joined,
     and per callstack. *)
  starts_joined: Cvalue.Model.t Kf_table.t;
  starts_by_callstack: Cvalue.Model.t Cs_table.t Kf_table.t;
  (* The answers to the requests joined over all callstacks, at the start of
     each function and before and after each statement. *)
  answers_start: Cvalue.Model.t Kf_table.t;
  answers_before: Cvalue.Model.t Stmt_table.t;
  answers_after: Cvalue.Model.t Stmt_table.t;
  (* The answers to the requests on one callstack before and after each
     statement, by statement and callstack. *)
  callstack_before: Cvalue.Model.t Cs_table.t Stmt_table.t;
  callstack_after: Cvalue.Model.t Cs_table.t Stmt_table.t;
  (* The callstacks that reach the point before and after each statement,
     with their states, as [get_state_by_callstack] answers them. *)
  reached_before: (Callstack.t * Cvalue.Model.t) list Stmt_table.t;
  reached_after: (Callstack.t * Cvalue.Model.t) list Stmt_table.t;
  (* For each function, its entries by callstack, see [entries_on]. *)
  entries_on: ((int * entry) list Cs_table.t * (int * entry) list) Kf_table.t;
  mutable indexed: bool;
  mutable pastes: int;
}

let new_derived () = {
  by_child = Int_table.create 17;
  by_callee = Kf_table.create 17;
  unrun_joined = Int_table.create 17;
  unrun_by_callstack = Int_table.create 17;
  unrun_frames = Int_table.create 17;
  starts_joined = Kf_table.create 17;
  starts_by_callstack = Kf_table.create 17;
  answers_start = Kf_table.create 17;
  answers_before = Stmt_table.create 17;
  answers_after = Stmt_table.create 17;
  callstack_before = Stmt_table.create 17;
  callstack_after = Stmt_table.create 17;
  reached_before = Stmt_table.create 17;
  reached_after = Stmt_table.create 17;
  entries_on = Kf_table.create 17;
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

(* Raised when a call below a hit was stored without its start state, or
   when a renaming does not rename every allocated block of a point, or is
   not injective on them. *)
exception Unavailable

(* [rename renaming point] is [point] with the blocks of the analysed call
   of its entry renamed to those of a member. Every allocated block of the
   point must be renamed, and no two to the same block, as [renaming] is
   then injective on the blocks of the point and none of its images is
   bound in the point unless it is renamed itself; raises [Unavailable]
   otherwise. A memory state is renamed by [Numbering.rewrite_model]. *)
let rename renaming (point: point) =
  match renaming with
  | [] -> point
  | pairs ->
    let domain = Base.Hptset.of_list (List.map fst pairs) in
    let images = Base.Hptset.of_list (List.map snd pairs) in
    let allocated =
      Base.Hptset.filter (function Base.Allocated _ -> true | _ -> false)
    in
    let blocks =
      Base.Hptset.union (Numbering.allocated_blocks point.inner)
        (allocated
           (Base.Hptset.union point.covered
              (Base.Hptset.union point.swept_every point.swept_some)))
    in
    if Base.Hptset.cardinal images <> List.length pairs
    || not (Base.Hptset.subset blocks domain)
    then raise Unavailable;
    let substitution = Base.substitution_from_list pairs in
    let rename_bases = Numbering.rewrite_bases substitution in
    { covered = rename_bases point.covered;
      inner = Numbering.rewrite_model substitution point.inner;
      swept_every = rename_bases point.swept_every;
      swept_some = rename_bases point.swept_some; }

(* The pointers to the blocks of [blocks] in [state] become escaping
   addresses: in place of the pointers if [exact], joined with them
   otherwise, as a release does. *)
let sweep ~exact blocks state =
  if Base.Hptset.is_empty blocks then state
  else
    let on_escaping ~b:_ ~itv:_ ~v:_ = () in
    Locals_scoping.make_escaping ~exact ~escaping:blocks ~on_escaping
      ~within:Base.SetLattice.top state

(* The state at a point whose Inner part is [point], of a call whose
   body-entry state is [entry]: [entry] with the sweep map of the point
   applied, without the covered blocks, and the Inner part. Only the covered
   blocks that the Inner part does not bind, the removal mask, are removed
   from [entry] before the Inner part is merged into it, so that the result
   shares the rest of [entry]. *)
let paste derived (point: point) entry =
  match entry, point.inner with
  | (Cvalue.Model.Bottom | Top), _ -> entry
  | Map _, (Cvalue.Model.Bottom | Top) ->
    derived.pastes <- derived.pastes + 1;
    point.inner
  | Map _, Cvalue.Model.Map inner ->
    derived.pastes <- derived.pastes + 1;
    let entry =
      sweep ~exact:true point.swept_every entry
      |> sweep ~exact:false point.swept_some
    in
    let bound = Base.Hptset.from_map (Cvalue.Model.shape inner) in
    let unbound = Base.Hptset.diff point.covered bound in
    let frame = Base.Hptset.fold Cvalue.Model.remove_base unbound entry in
    Cvalue.Model.merge ~into:frame point.inner

(* The start state of the call [below] made by the body of a member that
   uses the entry of the body through [renaming], whose body-entry state is
   [entry]. *)
let paste_call derived (below: below) renaming entry =
  match below.start, entry with
  | _, Cvalue.Model.Bottom -> Cvalue.Model.bottom
  | None, _ -> raise Unavailable
  | Some start, _ -> paste derived (rename renaming start) entry

(* Whether the call [below] may rename variables if it is a recursive call:
   its function has a formal or a local whose address is taken, or that an
   argument of the call copies, the argument being an lvalue of this
   variable. A recursive call renames these variables, see [Recursion.make],
   before its analysis by its body or by its specification is chosen. Eva
   copies fewer arguments: it assigns the scalar arguments of the functions
   that it treats as determinate. *)
let renames (below: below) =
  let kf = below.callee in
  let vars = Kernel_function.get_formals kf @ Kernel_function.get_locals kf in
  let args =
    match below.site.skind with
    | Instr (Call (_, _, args, _))
    | Instr (Local_init (_, ConsInit (_, args, _), _)) -> args
    | _ -> []
  in
  let copies vi (arg: Cil_types.exp) =
    match arg.enode with
    | Lval (Var v, _) -> Cil_datatype.Varinfo.equal v vi
    | _ -> false
  in
  List.exists
    (fun vi -> vi.Cil_types.vaddrof || List.exists (copies vi) args)
    vars

(* Whether a call of [callee] made on [callstack] is a recursive call. *)
let is_recursive callstack callee =
  List.exists (Kernel_function.equal callee) (Callstack.to_kf_list callstack)

(* The start state of the call [below] made on [callstack] by the body of a
   member that uses the entry of the body through [renaming], whose
   body-entry state is [entry]: top if the call is reachable and is a
   recursive call that renames variables, as given by [renames]. Below a
   member that crosses a recursion, [entry] is top, and so is the start
   state. *)
let call_below derived ~renames callstack (below: below) renaming entry =
  match paste_call derived below renaming entry with
  | Cvalue.Model.Bottom -> Cvalue.Model.bottom
  | Top | Map _ as state ->
    if renames && is_recursive callstack below.callee
    then Cvalue.Model.top
    else state

let calls_of table find key =
  Option.value ~default:[] (find table key)

(* The functions on the callstacks of the members of entry [id] whose body
   did not run, and whether one of these callstacks may cross a recursion.
   They are computed without any state, so that a joined request pastes the
   states per callstack only where a call may cross a recursion. *)
let rec unrun_frames store derived id =
  match Int_table.find_opt derived.unrun_frames id with
  | Some frames -> frames
  | None ->
    let add_frames callstack kfs =
      List.fold_left (Fun.flip Kernel_function.Set.add) kfs
        (Callstack.to_kf_list callstack)
    in
    let hits =
      match Int_table.find_opt store.entries id with
      | None -> Kernel_function.Set.empty
      | Some entry ->
        List.fold_left
          (fun acc (_, states) ->
             Cs_table.fold (fun callstack _ -> add_frames callstack)
               states.by_callstack acc)
          Kernel_function.Set.empty entry.hit_body_entries
    in
    let add (kfs, crossing as acc) (parent, below) =
      let parent_kfs, _ = unrun_frames store derived parent in
      if Kernel_function.Set.is_empty parent_kfs then acc
      else
        Kernel_function.Set.(add below.callee (union parent_kfs kfs)),
        crossing || may_cross store derived parent below
    in
    let frames =
      List.fold_left add (hits, false)
        (calls_of derived.by_child Int_table.find_opt id)
    in
    Int_table.replace derived.unrun_frames id frames;
    frames

(* Whether the call [below], made by the body of the members of entry
   [parent] whose body did not run, may cross a recursion: one of these
   members may, or the call renames variables and its function is on the
   callstack of one of them. *)
and may_cross store derived parent (below: below) =
  let kfs, crossing = unrun_frames store derived parent in
  not (Kernel_function.Set.is_empty kfs)
  && (crossing
      || Kernel_function.Set.mem below.callee kfs && renames below)

(* Joins [state] into the group of [renaming] of [callstack] in [table]. *)
let add_to_table table callstack renaming state =
  let groups = Option.value ~default:[] (Cs_table.find_opt table callstack) in
  Cs_table.replace table callstack (add_group renaming state groups)

(* Adds to [table], for each callstack and renaming of [states], the start
   state of the call [below] made by the body of the members of that
   callstack and renaming, in the group of the composed renaming. *)
let add_calls_below store derived table (below: below) states =
  let renames = renames below in
  Cs_table.iter
    (fun callstack groups ->
       List.iter
         (fun (renaming, entry) ->
            let state =
              call_below derived ~renames callstack below renaming entry
            in
            let callstack = Callstack.push below.callee below.site callstack in
            add_to_table table callstack (compose store renaming below) state)
         groups)
    states

(* The body-entry states of the members of entry [id] whose body did not run,
   per callstack and renaming. *)
let rec unrun_by_callstack store derived id =
  match Int_table.find_opt derived.unrun_by_callstack id with
  | Some table -> table
  | None ->
    let table = Cs_table.create 7 in
    Option.iter
      (fun entry ->
         List.iter
           (fun (renaming, states) ->
              Cs_table.iter
                (fun callstack state ->
                   add_to_table table callstack renaming state)
                states.by_callstack)
           entry.hit_body_entries)
      (Int_table.find_opt store.entries id);
    List.iter
      (fun (parent, below) ->
         let states = unrun_by_callstack store derived parent in
         add_calls_below store derived table below states)
      (calls_of derived.by_child Int_table.find_opt id);
    Int_table.replace derived.unrun_by_callstack id table;
    table

(* The body-entry states of the members of entry [id] whose body did not
   run, joined, grouped by renaming. *)
let rec unrun_joined store derived id =
  match Int_table.find_opt derived.unrun_joined id with
  | Some groups -> groups
  | None ->
    let hits =
      match Int_table.find_opt store.entries id with
      | None -> []
      | Some entry ->
        List.fold_left
          (fun acc (renaming, states) -> add_group renaming states.joined acc)
          [] entry.hit_body_entries
    in
    let groups =
      List.fold_left
        (fun acc (parent, below) ->
           List.fold_left
             (fun acc (renaming, state) -> add_group renaming state acc)
             acc (joined_call store derived parent below))
        hits (calls_of derived.by_child Int_table.find_opt id)
    in
    Int_table.replace derived.unrun_joined id groups;
    groups

(* The start states of the call [below] made by the body of the members of
   entry [parent] whose body did not run, joined, grouped by the renaming
   through which they use the entry of [below]. One paste per renaming of
   these members suffices, on their joined body-entry state, unless the call
   may cross a recursion: the states are then pasted per callstack. *)
and joined_call store derived parent below =
  if may_cross store derived parent below
  then
    let renames = renames below in
    Cs_table.fold
      (fun callstack groups acc ->
         List.fold_left
           (fun acc (renaming, entry) ->
              let state =
                call_below derived ~renames callstack below renaming entry
              in
              add_group (compose store renaming below) state acc)
           acc groups)
      (unrun_by_callstack store derived parent) []
  else
    List.map
      (fun (renaming, entry) ->
         compose store renaming below,
         paste_call derived below renaming entry)
      (unrun_joined store derived parent)

(* The start states of the calls below a hit to [kf], joined. *)
let starts_below_joined store derived kf =
  match Kf_table.find_opt derived.starts_joined kf with
  | Some state -> state
  | None ->
    let state =
      List.fold_left
        (fun acc (parent, below) ->
           Cvalue.Model.join acc
             (join_groups (joined_call store derived parent below)))
        Cvalue.Model.bottom (calls_of derived.by_callee Kf_table.find_opt kf)
    in
    Kf_table.replace derived.starts_joined kf state;
    state

(* The start states of the calls below a hit to [kf], per callstack. *)
let starts_below_by_callstack store derived kf =
  match Kf_table.find_opt derived.starts_by_callstack kf with
  | Some table -> table
  | None ->
    let groups = Cs_table.create 7 in
    List.iter
      (fun (parent, below) ->
         let states = unrun_by_callstack store derived parent in
         add_calls_below store derived groups below states)
      (calls_of derived.by_callee Kf_table.find_opt kf);
    let table = Cs_table.create 7 in
    Cs_table.iter
      (fun callstack groups ->
         Cs_table.replace table callstack (join_groups groups))
      groups;
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

(* The full state of the refused heap call of [entry] at [control_point], if
   reached. *)
let full_state entry control_point =
  match entry.inner, control_point with
  | Full { before; _ }, Domain_store.Before stmt ->
    Stmt_table.find_opt before stmt
  | Full { after; _ }, After stmt -> Stmt_table.find_opt after stmt
  | Full _, (Initial | Start _) | (Unknown | Known _), _ -> None

(* The point of the Inner part of [entry] at [control_point], if reached.
   None for a refused heap call, which has no Inner part: see
   [full_state]. *)
let find_point entry control_point =
  match entry.inner, control_point with
  | (Unknown | Full _), _ -> None
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

(* The initial state is unavailable when it was not recorded: the
   initialization of the globals failed and the analysis did not start. The
   legacy store then saves no state either, and its answer is top. *)
let is_available store control_point =
  cvalue_results_saved () && not store.unrecorded_hit &&
  match control_point with
  | Domain_store.Initial -> Option.is_some store.initial
  | Start _ -> true
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

(* [paste_groups derived point entry groups] joins the states that the
   rule gives at the point [point] of the Inner part of an entry, to the
   members of [groups] and to the members whose body-entry state is [entry]
   that use the entry through the identity: once on the join of [entry]
   and of the group of the identity, as without renamings, and once for
   each other group, from [point] renamed through the renaming of the
   group. *)
let paste_groups derived point entry groups =
  let identity, renamed = List.partition (fun (r, _) -> r = []) groups in
  let entry = Cvalue.Model.join entry (join_groups identity) in
  List.fold_left
    (fun acc (renaming, state) ->
       Cvalue.Model.join acc (paste derived (rename renaming point) state))
    (paste derived point entry) renamed

(* The state at [control_point], a point of the body of the function of the
   entry [id], of the members of this entry: those on [callstack], or all of
   them, joined. The only member of the entry of a heap call is its analysed
   call; the state of a refused heap call is its full state. *)
let entry_state store derived ?callstack control_point (id, entry) =
  match entry.inner with
  | Full _ ->
    let state =
      Option.value ~default:Cvalue.Model.bottom
        (full_state entry control_point)
    in
    begin match callstack with
      | None -> state
      | Some callstack -> analysed_on callstack (fun _ -> state) entry
    end
  | Unknown | Known _ ->
    match find_point entry control_point with
    | None -> Cvalue.Model.bottom
    | Some point ->
      match callstack with
      | None ->
        paste_groups derived point entry.analysed.body_entry
          (unrun_joined store derived id)
      | Some callstack ->
        paste_groups derived point
          (analysed_on callstack (fun a -> a.body_entry) entry)
          (Option.value ~default:[]
             (Cs_table.find_opt (unrun_by_callstack store derived id)
                callstack))

(* For the function [kf]: its entries by callstack, those whose analysed call
   is on the callstack or that have on it a member whose body did not run,
   each list in the order of [entries_with_ids]; and its entries on which
   [unrun_by_callstack] raises [Unavailable]. The entry of a heap call has no
   member whose body did not run: it is listed on the callstack of its
   analysed call only. *)
let entries_on store derived kf =
  match Kf_table.find_opt derived.entries_on kf with
  | Some index -> index
  | None ->
    let table = Cs_table.create 17 in
    let add (id, _ as member) callstack =
      match Cs_table.find_opt table callstack with
      | Some ((id', _) :: _) when id' = id -> ()
      | previous ->
        Cs_table.replace table callstack
          (member :: Option.value ~default:[] previous)
    in
    let unavailable =
      List.fold_left
        (fun unavailable (id, entry as member) ->
           add member entry.analysed.callstack;
           match entry.inner with
           | Full _ -> unavailable
           | Unknown | Known _ ->
             match unrun_by_callstack store derived id with
             | states ->
               Cs_table.iter (fun callstack _ -> add member callstack) states;
               unavailable
             | exception Unavailable -> member :: unavailable)
        [] (List.rev (entries_with_ids store kf))
    in
    let index = table, unavailable in
    Kf_table.replace derived.entries_on kf index;
    index

(* The state at [control_point], a point of the body of [kf], joined over all
   callstacks or on [callstack]: the join of the states of the entries of
   [kf], in the order of [entries_with_ids].
   On [callstack], only the entries that [entries_on] lists for [callstack]
   are joined. The state on [callstack] of any other entry is Bottom: its
   body-entry state on [callstack] is the join of two Bottom states, and
   [paste] gives Bottom on Bottom. [Cvalue.Model.join] gives its other
   argument when one is Bottom, so leaving these entries out of the join
   gives the same value, the order of the others being kept. The state of an
   entry with a point at [control_point] computes [unrun_by_callstack] on it:
   if [Unavailable] is raised on such an entry, it is raised here as well. *)
let point_state store derived ?callstack control_point kf =
  match callstack with
  | None ->
    List.map (entry_state store derived control_point)
      (entries_with_ids store kf)
    |> join_all
  | Some callstack ->
    let table, unavailable = entries_on store derived kf in
    let has_point (_, entry) =
      Option.is_some (find_point entry control_point)
    in
    if List.exists has_point unavailable then raise Unavailable;
    Option.value ~default:[] (Cs_table.find_opt table callstack)
    |> List.map (entry_state store derived ~callstack control_point)
    |> join_all

(* [memo table find replace key f] is the answer [f ()] for [key], memoised
   in [table]. *)
let memo table find replace key f =
  match find table key with
  | Some state -> state
  | None ->
    let state = f () in
    replace table key state;
    state

(* The answers before and after the statements are memoised, joined over all
   callstacks and for each callstack. A memoised answer is the state that
   [point_state] computed for the same point and callstack, from the store,
   which does not change once the analysis has ended, and from memoised
   states that do not change either: [point_state] would compute the same
   value again. The passes after the iteration ask for the same states
   several times: the statuses of the properties evaluate each property of a
   statement on each callstack that reaches it, with the labels of its
   function. If [Unavailable] is raised, no answer is memoised, and the next
   request raises it again. *)
let get_state ?callstack control_point =
  let store = Store.get () in
  if not (is_available store control_point) then `Top
  else
    let derived = derived store in
    count_pastes derived @@ fun () ->
    let point_state stmt ~joined ~by_callstack =
      let kf = Kernel_function.find_englobing_kf stmt in
      let compute () = point_state store derived ?callstack control_point kf in
      match callstack with
      | None -> memo joined Stmt_table.find_opt Stmt_table.replace stmt compute
      | Some callstack ->
        let table =
          memo by_callstack Stmt_table.find_opt Stmt_table.replace stmt
            (fun () -> Cs_table.create 7)
        in
        memo table Cs_table.find_opt Cs_table.replace callstack compute
    in
    try
      match control_point with
      | Initial ->
        begin match store.initial, callstack with
          | None, _ -> `Top
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
      | Before stmt ->
        point_state stmt ~joined:derived.answers_before
          ~by_callstack:derived.callstack_before
        |> to_result
      | After stmt ->
        point_state stmt ~joined:derived.answers_after
          ~by_callstack:derived.callstack_after
        |> to_result
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
           match entry.inner with
           | Full _ ->
             Option.iter (add table entry.analysed.callstack)
               (full_state entry control_point)
           | Unknown | Known _ ->
             match find_point entry control_point with
             | None -> ()
             | Some point ->
               let analysed = entry.analysed in
               add table analysed.callstack
                 (paste derived point analysed.body_entry);
               Cs_table.iter
                 (fun callstack groups ->
                    add table callstack
                      (paste_groups derived point Cvalue.Model.bottom groups))
                 (unrun_by_callstack store derived id))
        (entries_with_ids store kf)
  end;
  table

(* The answers before and after the statements are memoised, as those of
   [get_state] and for the same reasons. *)
let get_state_by_callstack control_point =
  let store = Store.get () in
  if not (is_available store control_point) then `Top
  else
    let derived = derived store in
    count_pastes derived @@ fun () ->
    let compute () =
      let table = states_by_callstack store derived control_point in
      let reached =
        Cs_table.fold
          (fun callstack state acc ->
             match state with
             | Cvalue.Model.Bottom -> acc
             | Top | Map _ -> (callstack, state) :: acc)
          table []
      in
      List.sort (fun (a, _) (b, _) -> Callstack.compare a b) reached
    in
    let memoised table stmt =
      memo table Stmt_table.find_opt Stmt_table.replace stmt compute
    in
    try
      let reached =
        match control_point with
        | Before stmt -> memoised derived.reached_before stmt
        | After stmt -> memoised derived.reached_after stmt
        | Initial | Start _ -> compute ()
      in
      match reached with
      | [] -> `Bottom
      | list -> `Value list
    with Unavailable -> `Top

(* ----- For the tests ----------------------------------------------------- *)

type inner_view = {
  covered: Base.Hptset.t;
  inner: Cvalue.Model.t;
  swept_every: Base.Hptset.t;
  swept_some: Base.Hptset.t;
}

type point_view =
  | Full_states
  | No_point
  | Inner of inner_view

let point_view ~id control_point =
  match Int_table.find_opt (Store.get ()).entries id with
  | None -> No_point
  | Some { inner = Full _; _ } -> Full_states
  | Some entry ->
    match find_point entry control_point with
    | None -> No_point
    | Some point ->
      Inner { covered = point.covered; inner = point.inner;
              swept_every = point.swept_every;
              swept_some = point.swept_some }

let rule ~id ?(renaming = []) ~body_entry control_point =
  let store = Store.get () in
  match Int_table.find_opt store.entries id with
  | None -> None
  | Some entry ->
    try
      Option.map
        (fun point -> paste (derived store) (rename renaming point) body_entry)
        (find_point entry control_point)
    with Unavailable -> None

let members ~id =
  let store = Store.get () in
  let table = unrun_by_callstack store (derived store) id in
  Cs_table.fold
    (fun callstack groups acc ->
       List.map (fun (renaming, state) -> callstack, renaming, state) groups
       @ acc)
    table []
  |> List.sort (fun (a, _, _) (b, _, _) -> Callstack.compare a b)
