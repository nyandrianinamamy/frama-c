(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module SaveCounter =
  State_builder.SharedCounter(struct let name = "Mem_exec.save_counter" end)

let new_counter, current_counter =
  let cur = ref (-1) in
  (fun () -> cur := SaveCounter.next (); !cur),
  (fun () -> !cur)

let cleanup_ref = ref (fun () -> ())

(* TODO: it would be great to clear also the tables within the plugins. Export
   self and add dependencies *)
let cleanup_results () = !cleanup_ref ()

exception TooImprecise

(* Extract all the bases from a zone *)
let bases = function
  | Memory_zone.Top (Base.SetLattice.Top, _) -> raise TooImprecise
  | Memory_zone.Top (Base.SetLattice.Set s, _) -> s
  | Memory_zone.Map m -> Base.Hptset.from_map (Memory_zone.shape m)

(* ----- Snapshot of the mentioned blocks ---------------------------------- *)

(* The validity record of an allocated block: its bounds, which the analysis
   mutates in place, or a validity that it does not mutate. *)
type record =
  | Variable of { min_alloc: Z.t; max_alloc: Z.t }
  | Fixed of Base.validity

(* What the analysis of a call reads of an allocated block, besides its
   content: its strength, its validity record, its type and its kind. *)
type block = {
  weak: bool;
  record: record;
  typ: Cil_types.typ;
  kind: Base.deallocation;
}

let equal_record r1 r2 =
  match r1, r2 with
  | Variable v1, Variable v2 ->
    Z.equal v1.min_alloc v2.min_alloc && Z.equal v1.max_alloc v2.max_alloc
  | Fixed v1, Fixed v2 -> Base.Validity.equal v1 v2
  | (Variable _ | Fixed _), _ -> false

let equal_block b1 b2 =
  b1.weak = b2.weak && equal_record b1.record b2.record
  && Cil_datatype.Typ.equal b1.typ b2.typ && b1.kind = b2.kind

(* The block of an allocated base as it is now. The record and the type are
   copied: the analysis mutates them in place afterwards. *)
let take_block = function
  | Base.Allocated (vi, kind, validity) ->
    let record =
      match validity with
      | Base.Variable v ->
        Variable { min_alloc = v.min_alloc; max_alloc = v.max_alloc }
      | validity -> Fixed validity
    in
    let weak = Base.is_weak_validity validity in
    Some { weak; record; typ = vi.vtype; kind }
  | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> None

(* A snapshot: the block of each mentioned base, when the cache entry of the
   call was stored. *)
module Snapshot = struct
  include Datatype.Make
      (struct
        type t = (Base.t * block) list
        include Datatype.Undefined
        let name = "Mem_exec.Snapshot"
        let reprs = [ [] ]
        let mem_project = Datatype.never_any_project
      end)

  (* The snapshot of a call that mentions no allocated block, and of every
     call stored without -eva-hit-log. *)
  let empty = []

  let take bases =
    Base.Hptset.fold
      (fun base acc ->
         match take_block base with
         | Some block -> (base, block) :: acc
         | None -> acc)
      bases []

  (* Whether each base of the snapshot has its block now. *)
  let holds snapshot =
    List.for_all
      (fun (base, block) ->
         match take_block base with
         | Some now -> equal_block block now
         | None -> false)
      snapshot
end

let is_allocated = function
  | Base.Allocated _ -> true
  | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> false

(* Adds to [acc] the allocated bases that [v] may point to. Raises
   [TooImprecise] if [v] may point to an unknown set of bases. *)
let add_targets v acc =
  match Cvalue.V.get_bases v with
  | Base.SetLattice.Top -> raise TooImprecise
  | Base.SetLattice.Set bases ->
    Base.Hptset.union (Base.Hptset.filter is_allocated bases) acc

(* Adds to [acc] the allocated bases that a value of [state] may point to. *)
let add_targets_of_state state acc =
  match state with
  | Cvalue.Model.Bottom -> acc
  | Cvalue.Model.Top -> raise TooImprecise
  | Cvalue.Model.Map map ->
    let add_value v acc =
      add_targets (Cvalue.V_Or_Uninitialized.get_v v) acc
    in
    Cvalue.Model.fold
      (fun _base offsm acc ->
         Cvalue.V_Offsetmap.fold_on_values add_value offsm acc)
      map acc


(* The calls that memexec does not reuse although a stored result has their
   input state: the snapshot of a mentioned block differs. *)
let snapshot_misses =
  Statistics.(register_function_stat "hit-log-snapshot-misses" Int)

let counter = ref 0

module Make
    (Value : Engine_abstractions_sig.Value)
    (Domain : Engine_abstractions_sig.Domain)
= struct

  incr counter;

  module CallOutput = Datatype.List (Datatype.Pair (Partition.Key) (Domain))

  module StoredResult =
    Datatype.Quadruple
      (Base.Hptset)  (* Set of bases possibly read or written by the call. *)
      (CallOutput)   (* The resulting states of the call. *)
      (Datatype.Int) (* Call number, for plugins *)
      (Snapshot)     (* The snapshot of the bases mentioned by the call,
                        empty unless it was stored with [~snapshot:true]. *)

  (* Map from input states to outputs (summary and state). An input state
     can have several stored results, which differ by their snapshots. *)
  module CallEffect = Domain.Hashtbl.Make (StoredResult)

  (* Map from useful input bases to call effects. *)
  module InputBasesToCallEffect = Base.Hptset.Hashtbl.Make (CallEffect)

  (* List of the arguments of a call. *)
  module ActualArgs =
    Datatype.List_with_collections (Datatype.Option (Value)) (* None is bottom *)

  (* Map from the arguments of a call to stored results. *)
  module ArgsToStoredCalls = ActualArgs.Map.Make (InputBasesToCallEffect)

  module PreviousCalls =
    Kernel_function.Make_Table
      (Eva_utils.Do_Not_Marshal (ArgsToStoredCalls))
      (struct
        let size = 17
        let dependencies = [Self.state]
        let name = "Mem_exec.PreviousCalls(" ^ string_of_int !counter ^ ")"
      end)

  let cleanup = !cleanup_ref
  let () = cleanup_ref := fun () -> cleanup (); PreviousCalls.clear ()

  (* Extends the input [bases] of a function [kf] by adding all bases related to
     these inputs in state [state]. We perform a fixpoint over [Domain.relate]
     to compute the transitive closure of the relations in [state] on [bases].
     Indeed, if a domain D1 relates x and y, and a domain D2 relates y and z,
     then x and z are also related.
     All bases related to the input [bases] should be taken into account when
     applying the memexec cache, as their values may impact the analysis of [kf]
     starting from state [state].
     As a full fixpoint computation could be costly, we stop after [count] calls
     to [Domain.relate] and we disable memexec if a fixpoint is not reached. *)
  let rec expand_inputs_with_relations count kf bases state =
    let related_bases = Domain.relate bases state in
    match related_bases with
    | Base.SetLattice.Top -> related_bases
    | Base.SetLattice.Set new_bases ->
      let expanded_bases = Base.Hptset.union new_bases bases in
      if Base.Hptset.equal expanded_bases bases
      then Base.SetLattice.inject expanded_bases
      else if count <= 0 then Base.SetLattice.top
      else expand_inputs_with_relations (count - 1) kf expanded_bases state

  let get_cvalue =
    match Value.get Main_values.CVal.key with
    | Some get -> get
    | None -> fun _ -> Cvalue.V.top

  (* The snapshot of the allocated bases that a call mentions: the bases of
     its key [bases], and those that a pointer value of its arguments [args]
     or of [state], its start state on its key, may point to. A mentioned
     base outside the key is not entered. Raises [TooImprecise] if one of
     these values may point to an unknown set of bases.
     The call is stored after its analysis, but the blocks of the snapshot
     are those of its start: a call that changes the validity or the type
     of an allocated block receives a heap effect, and is not stored. *)
  let take_snapshot bases args state =
    let add_arg acc = function
      | `Bottom -> acc
      | `Value v -> add_targets (get_cvalue v) acc
    in
    let blocks = Base.Hptset.filter is_allocated bases in
    let blocks = List.fold_left add_arg blocks args in
    let blocks =
      add_targets_of_state (Domain.get_cvalue_or_top state) blocks
    in
    Snapshot.take blocks

  (* With [~snapshot:false], the store of memexec without -eva-hit-log: the
     stored result has the empty snapshot, a constant. *)
  let store_computed_call ~snapshot kf input_state args
      (call_result: (Partition.key * Domain.t) list) =
    match Transfer_stmt.current_kf_inout () with
    | None -> ()
    | Some inout ->
      try
        (* The matching key: the bases read by the call, those read by its
           annotations, and those it writes on any path, whether the path
           returns or not, including the bases it surely overwrites. *)
        let input_bases =
          let input_bases = bases inout.Inout_type.over_inputs in
          let logic_input_bases = bases inout.Inout_type.over_logic_inputs in
          let output_bases = bases inout.Inout_type.over_outputs in
          Base.Hptset.(union input_bases (union logic_input_bases output_bases))
        in
        let input_bases =
          expand_inputs_with_relations 2 kf input_bases input_state
        in
        let input_bases = match input_bases with
          | Base.SetLattice.Top -> raise TooImprecise
          | Base.SetLattice.Set bases -> bases
        in
        let state_input = Domain.filter input_bases input_state in
        let snapshot =
          if snapshot then take_snapshot input_bases args state_input
          else Snapshot.empty
        in
        (* Output bases, that is bases that are copy-pasted on a reuse: the
           key, which includes the written bases and the input bases, as the
           latter may get reduced during the call. *)
        let all_output_bases = input_bases in
        (* Adds the fake varinfo used for the result of [kf] to the
           output_bases. *)
        let return_varinfo = Library_functions.get_retres_vi kf in
        let return_base = Option.map Base.of_varinfo return_varinfo in
        let add b = Base.Hptset.add b all_output_bases in
        let all_output_bases =
          Option.fold ~some:add ~none:all_output_bases return_base
        in
        let clear (key,state) =
          key, Domain.filter all_output_bases state
        in
        let outputs = List.map clear call_result in
        let call_number = current_counter () in
        let map_a =
          try PreviousCalls.find kf
          with Not_found -> ActualArgs.Map.empty
        in
        let hkf =
          let args =
            List.map (function `Bottom -> None | `Value v -> Some v) args in
          try ActualArgs.Map.find args map_a
          with Not_found ->
            let h = Base.Hptset.Hashtbl.create 11 in
            let map_a = ActualArgs.Map.add args h map_a in
            PreviousCalls.replace kf map_a;
            h
        in
        let hkb =
          try Base.Hptset.Hashtbl.find hkf input_bases
          with Not_found ->
            let h = Domain.Hashtbl.create 11 in
            Base.Hptset.Hashtbl.add hkf input_bases h;
            h
        in
        Domain.Hashtbl.add hkb state_input
          (all_output_bases, outputs, call_number, snapshot);
      with
      | TooImprecise
      | Kernel_function.No_Statement
      | Not_found -> ()


  exception Result_found of CallOutput.t * int

  (** Find a previous execution in [map_inputs] that matches [st].
      raise [Result_found] when this execution exists, or do nothing. This is
      the lookup of memexec without -eva-hit-log: the snapshot of the stored
      results is not read. *)
  let find_match_in_previous (map_inputs: InputBasesToCallEffect.t) state =
    let aux_previous_call binputs hstates =
      let brelated = Domain.relate binputs state in
      if not Base.SetLattice.(is_included brelated (inject binputs))
      then ()
      else
        (* restrict [state] to the inputs of this call *)
        let st_filtered = Domain.filter binputs state in
        try
          let bases, outputs, i, _ = Domain.Hashtbl.find hstates st_filtered in
          (* We have found a previous execution, in which the outputs are
             [outputs]. Copy them in [state] and return this result. *)
          let process (key,output) =
            key,
            Domain.reuse bases ~current_input:state ~previous_output:output
          in
          let outputs = List.map process outputs in
          raise (Result_found (outputs, i))
        with Not_found -> ()
    in
    Base.Hptset.Hashtbl.iter aux_previous_call map_inputs

  (** As [find_match_in_previous], with the snapshot: an execution matches
      [st] only if its snapshot holds now. If several do, the most recent
      one. Otherwise, returns whether a previous execution has the input
      state [st]: the snapshot of a mentioned block differs. *)
  let find_match_with_snapshot (map_inputs: InputBasesToCallEffect.t) state =
    let same_input = ref false in
    let aux_previous_call binputs hstates =
      let brelated = Domain.relate binputs state in
      if not Base.SetLattice.(is_included brelated (inject binputs))
      then ()
      else
        (* restrict [state] to the inputs of this call *)
        let st_filtered = Domain.filter binputs state in
        (* The stored results of this input state, the most recent first,
           and the first of them whose snapshot holds now. *)
        let stored = Domain.Hashtbl.find_all hstates st_filtered in
        let holds (_, _, _, snapshot) = Snapshot.holds snapshot in
        match List.find_opt holds stored with
        | None -> if stored <> [] then same_input := true
        | Some (bases, outputs, i, _) ->
          let process (key,output) =
            key,
            Domain.reuse bases ~current_input:state ~previous_output:output
          in
          let outputs = List.map process outputs in
          raise (Result_found (outputs, i))
    in
    Base.Hptset.Hashtbl.iter aux_previous_call map_inputs;
    !same_input

  (* With [~snapshot:false], the lookup of memexec without -eva-hit-log. *)
  let reuse_previous_call ~snapshot kf state args =
    try
      let previous_kf = PreviousCalls.find kf in
      let args = List.map (function `Bottom -> None | `Value v -> Some v) args in
      let previous = ActualArgs.Map.find args previous_kf in
      if not snapshot then find_match_in_previous previous state
      else if find_match_with_snapshot previous state
      then Statistics.incr snapshot_misses kf;
      Statistics.(incr memexec_misses kf);
      None
    with
    | Not_found ->
      Statistics.(incr memexec_misses) kf;
      None
    | Result_found (outputs, i) ->
      Statistics.(incr memexec_hits) kf;
      let call_result = outputs in
      Some (call_result, i)

  let has_previous_call kf state args =
    try
      let previous_kf = PreviousCalls.find kf in
      let args =
        List.map (function `Bottom -> None | `Value v -> Some v) args
      in
      let previous = ActualArgs.Map.find args previous_kf in
      find_match_in_previous previous state;
      false
    with
    | Not_found -> false
    | Result_found _ -> true

end
