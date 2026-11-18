(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Bases = Base.SetLattice
module Zone = Memory_zone

module Result = struct
  (* Order used to select one reason for the storage disposition. *)
  type refusal =
    | Indirect_call | Builtin | Sweep | Contract | Annotation | Nested_call
    | Allocated_block | Footprint_top | Side_table

  let refusal_id = function
    | Indirect_call -> "indirect-call"
    | Builtin -> "builtin"
    | Sweep -> "sweep"
    | Contract -> "contract"
    | Annotation -> "annotation"
    | Nested_call -> "nested-call"
    | Allocated_block -> "allocated-block"
    | Footprint_top -> "footprint-top"
    | Side_table -> "side-table"

  type recorded =
    | Reached | States | Callers | Guards | Alarms | Statuses | Zones | Holders

  type t = {
    reads : Bases.t;
    writes : Bases.t;
    exit_writes : Bases.t;
    sure_writes : Base.Hptset.t;
    designated : Bases.t;
    recorded : recorded list;
    refusals : refusal list;
  }

  module Hooks = Hook.Build (struct type nonrec t = Callstack.t * t end)

  let on_result f = Hooks.extend (fun (stack, result) -> f stack result)
end

open Result

type writes = { may : Bases.t; sure : Zone.t }

let no_writes = { may = Bases.bottom; sure = Zone.bottom }

type edge = { src : int; dst : int; writes : writes }

type recording = {
  mutable reads : Bases.t;
  mutable writes : Bases.t;
  mutable designated : Bases.t;
  mutable recorded : recorded list;
  mutable refusals : refusal list;
  mutable transition : writes option;
  edges : (int, edge) Hashtbl.t;
  mutable paths : (int * int) option;
  mutable unlocated_write : bool;
}

let current : recording option ref = ref None

let[@inline always] is_recording () = Option.is_some !current

let without_recording f =
  match !current with
  | None -> f ()
  | previous ->
    current := None;
    Fun.protect f ~finally:(fun () -> current := previous)

let add_refusal r reason =
  if not (List.mem reason r.refusals) then r.refusals <- reason :: r.refusals

let[@inline always] refuse reason =
  match !current with
  | None -> ()
  | Some r -> add_refusal r reason

let record_table r table =
  if not (List.mem table r.recorded) then
    r.recorded <- table :: r.recorded

let[@inline always] record table =
  match !current with
  | None -> ()
  | Some r -> record_table r table

let check_bases r = function
  | Bases.Top -> add_refusal r Footprint_top
  | Bases.Set bases ->
    let allocated = function Base.Allocated _ -> true | _ -> false in
    if Base.Hptset.exists allocated bases then add_refusal r Allocated_block

let add_read r location =
  let bases = Addresses.Bits.get_bases location.Locations.addr in
  check_bases r bases;
  r.reads <- Bases.join r.reads bases

let[@inline always] read location =
  match !current with
  | None -> ()
  | Some r -> add_read r location

let check_location value =
  match !current with
  | None -> ()
  | Some r -> check_bases r (Cvalue.V.get_bases value)

let add_designated r bases =
  let bases =
    match bases with
    | Bases.Top -> Bases.top
    | Bases.Set bases -> Bases.inject (Base.Hptset.remove Base.null bases)
  in
  check_bases r bases;
  r.designated <- Bases.join r.designated bases

let[@inline always] designate value =
  match !current with
  | None -> ()
  | Some r -> add_designated r (Cvalue.V.get_bases value)

let designate_bits addr =
  match !current with
  | None -> ()
  | Some r -> add_designated r (Addresses.Bits.get_bases addr)

let add_write r may sure =
  r.writes <- Bases.join r.writes may;
  match r.transition with
  | None -> r.unlocated_write <- true
  | Some w ->
    let may = Bases.join w.may may in
    let sure = Zone.link w.sure sure in
    r.transition <- Some {may; sure}

let add_possible_write r bases =
  check_bases r bases;
  add_write r bases Zone.bottom

let may_write location =
  match !current with
  | None -> ()
  | Some r ->
    add_possible_write r (Addresses.Bits.get_bases location.Locations.addr)

let may_write_base base =
  match !current with
  | None -> ()
  | Some r ->
    add_possible_write r (Bases.inject (Base.Hptset.singleton base))

let unknown_write () =
  Option.iter (fun r -> add_write r Bases.top Zone.bottom) !current

let () = Origin.on_history_access (fun () -> refuse Side_table)

let write location =
  match !current with
  | None -> ()
  | Some r ->
    let may = Addresses.Bits.get_bases location.Locations.addr in
    check_bases r may;
    let sure =
      if Locations.cardinal_zero_or_one location
      then Locations.enumerate_bits_under location
      else Zone.bottom
    in
    add_write r may sure

let unknown_read reason =
  Option.iter
    (fun r -> add_refusal r reason; r.reads <- Bases.top)
    !current

let unknown_access reason =
  Option.iter
    (fun r ->
       add_refusal r reason;
       r.reads <- Bases.top;
       add_write r Bases.top Zone.bottom)
    !current

let transfer ~id ~src ~dst f input =
  match !current with
  | None -> f input
  | Some r ->
    let previous = r.transition in
    r.transition <- Some no_writes;
    let finish () =
      let writes = Option.get r.transition in
      r.transition <- previous;
      writes
    in
    match f input with
    | exception exn ->
      let bt = Printexc.get_raw_backtrace () in
      ignore (finish ());
      Printexc.raise_with_backtrace exn bt
    | output ->
      let writes = finish () in
      if output <> [] then begin
        let writes =
          match Hashtbl.find_opt r.edges id with
          | None -> writes
          | Some edge ->
            { may = Bases.join writes.may edge.writes.may;
              sure = Zone.meet writes.sure edge.writes.sure }
        in
        Hashtbl.replace r.edges id {src; dst; writes}
      end;
      output

(* The graph contains only transfers that produced a successor. Quotienting
   by the automaton vertices can join paths from different abstract states. *)
let may_reach_exit edges exit =
  let incoming = Hashtbl.create 17 in
  Hashtbl.iter (fun _ e -> Hashtbl.add incoming e.dst e) edges;
  let seen = Hashtbl.create 17 in
  let writes = ref Bases.bottom in
  let rec visit = function
    | [] -> !writes
    | v :: rest when Hashtbl.mem seen v -> visit rest
    | v :: rest ->
      Hashtbl.add seen v ();
      let enqueue rest (e : edge) =
        writes := Bases.join !writes e.writes.may;
        e.src :: rest
      in
      visit (List.fold_left enqueue rest (Hashtbl.find_all incoming v))
  in
  visit [exit]

(* Propagate definitely written bits from the entry. Their intersection at
   a join retains only the bits written on every incoming path. *)
let must_reach_exit edges entry exit =
  let outgoing = Hashtbl.create 17 in
  Hashtbl.iter (fun _ e -> Hashtbl.add outgoing e.src e) edges;
  let written = Hashtbl.create 17 in
  let work = Queue.create () in
  let enqueue v zone =
    Hashtbl.replace written v zone;
    Queue.push v work
  in
  enqueue entry Zone.bottom;
  while not (Queue.is_empty work) do
    let src = Queue.pop work in
    let before = Hashtbl.find written src in
    let propagate (e : edge) =
      let after = Zone.link before e.writes.sure in
      match Hashtbl.find_opt written e.dst with
      | None -> enqueue e.dst after
      | Some previous ->
        let merged = Zone.meet previous after in
        if not (Zone.equal previous merged) then enqueue e.dst merged
    in
    List.iter propagate (Hashtbl.find_all outgoing src)
  done;
  let full_block base bits acc =
    match Base.validity base with
    | Base.Known (lo, hi)
      when Int_Intervals.is_included (Int_Intervals.inject_bounds lo hi) bits ->
      Base.Hptset.add base acc
    | _ -> acc
  in
  match Hashtbl.find_opt written exit with
  | None -> Base.Hptset.empty
  | Some bits -> Zone.fold_i full_block bits Base.Hptset.empty

let finish_paths ~entry ~exit ~returns =
  if returns then Option.iter (fun r -> r.paths <- Some (entry, exit)) !current

let capture stack compute =
  if not (Parameters.CacheCollect.get ()) then compute (), None
  else
    let previous = !current in
    let r = {
      reads = Bases.bottom;
      writes = Bases.bottom;
      designated = Bases.bottom;
      recorded = [];
      refusals = [];
      transition = None;
      edges = Hashtbl.create 17;
      paths = None;
      unlocated_write = false;
    } in
    current := Some r;
    let output = Fun.protect compute ~finally:(fun () -> current := previous) in
    let exit_writes, sure_writes =
      match r.paths with
      | None -> Bases.bottom, Base.Hptset.empty
      | Some _ when r.unlocated_write -> r.writes, Base.Hptset.empty
      | Some (entry, exit) ->
        may_reach_exit r.edges exit, must_reach_exit r.edges entry exit
    in
    let result = {
      reads = r.reads;
      writes = r.writes;
      exit_writes;
      sure_writes;
      designated = r.designated;
      recorded = List.sort compare r.recorded;
      refusals = List.sort compare r.refusals;
    } in
    without_recording (fun () -> Hooks.apply (stack, result));
    output, Some result

let verdict (r : Result.t) =
  match r.refusals with
  | [] -> Ok ()
  | reason :: _ -> Error reason
