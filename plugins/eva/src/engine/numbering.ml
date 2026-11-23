(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* ----- Placeholders ----------------------------------------------------- *)

(* The placeholders created in this analysis, by pool and number: the key of
   the placeholder [n] of a pool is [2n], or [2n + 1] in the weak pool. *)
module Placeholders =
  State_builder.Int_hashtbl
    (Base)
    (struct
      let name = "Eva.Numbering.Placeholders"
      let dependencies = [ Self.state ]
      let size = 17
    end)

(* The number of each placeholder. *)
module Numbers =
  State_builder.Hashtbl
    (Base.Hashtbl)
    (Datatype.Int)
    (struct
      let name = "Eva.Numbering.Numbers"
      let dependencies = [ Self.state ]
      let size = 17
    end)

(* A placeholder is an allocated base, so that [Base.is_weak] gives its
   strength; nothing reads the rest of its validity record, its type or
   its kind. It is not declared as a global of the AST. *)
let create_placeholder ~weak n =
  let name = Printf.sprintf "#%d%s" n (if weak then "_w" else "") in
  let vi =
    Cil.makeGlobalVar ~source:false ~temp:false name Cil_const.voidType
  in
  let validity =
    Base.Variable
      (Base.create_variable_validity ~weak
         ~min_alloc:Z.minus_one ~max_alloc:Z.minus_one)
  in
  let base = Base.register_allocated_var vi Base.Malloc validity in
  Numbers.add base n;
  base

let placeholder ~weak n =
  let key = 2 * n + if weak then 1 else 0 in
  Placeholders.memo (fun _ -> create_placeholder ~weak n) key

let placeholder_number base = Numbers.find_opt base

(* ----- Numbering -------------------------------------------------------- *)

type discovery =
  | Argument of int
  | Content of Base.t
  | Candidate
  | No_root

exception Unknown_targets

module IntMap = Datatype.Int.Map

type t = {
  next: int;                      (* The number of the next block. *)
  examined: int;                  (* The blocks below it are examined. *)
  numbers: int Base.Map.t;        (* The number of each numbered block. *)
  blocks: (Base.t * bool * discovery) IntMap.t;
  (* Each numbered block by its number, with its strength and discovery. *)
}

let empty =
  { next = 0; examined = 0; numbers = Base.Map.empty; blocks = IntMap.empty }

let is_allocated = function
  | Base.Allocated _ -> true
  | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> false

let by_identifier bases = List.sort Base.compare (Base.Hptset.elements bases)

let add_block discovery t base =
  if not (is_allocated base) || Base.Map.mem base t.numbers then t
  else
    let n = t.next in
    { t with
      next = n + 1;
      numbers = Base.Map.add base n t.numbers;
      blocks = IntMap.add n (base, Base.is_weak base, discovery) t.blocks }

let add discovery bases t = List.fold_left (add_block discovery) t bases

(* Numbers the allocated targets of [v], by increasing identifier. *)
let add_targets discovery t v =
  match Cvalue.V.get_bases v with
  | Base.SetLattice.Top -> raise Unknown_targets
  | Base.SetLattice.Set bases -> add discovery (by_identifier bases) t

let arguments args t =
  let add_argument (i, t) = function
    | `Bottom -> i + 1, t
    | `Value v -> i + 1, add_targets (Argument i) t v
  in
  snd (List.fold_left add_argument (0, t) args)

(* Walks the content of [base] in [state]: its values by increasing offset. *)
let walk state t base =
  let add_value _interval (v, _size, _offset) t =
    add_targets (Content base) t (Cvalue.V_Or_Uninitialized.get_v v)
  in
  match state with
  | Cvalue.Model.Top -> raise Unknown_targets
  | Cvalue.Model.Bottom -> t
  | Cvalue.Model.Map _ ->
    match Cvalue.Model.find_base base state with
    | `Value offsetmap -> Cvalue.V_Offsetmap.fold add_value offsetmap t
    | `Bottom -> t
    | `Top -> raise Unknown_targets
    | exception Not_found -> t

let roots bases state t = List.fold_left (walk state) t (by_identifier bases)

let rec drain ~is_key state t =
  if t.examined >= t.next then t
  else
    let n = t.examined in
    let base, _, _ = IntMap.find n t.blocks in
    let t = { t with examined = n + 1 } in
    let t = if is_key n base then walk state t base else t in
    drain ~is_key state t

let of_entry ~candidates ~args ~key state =
  let is_key _ base = Base.Hptset.mem base key in
  let allocated, others = Base.Hptset.partition is_allocated key in
  empty
  |> arguments args
  |> roots others state
  |> drain ~is_key state
  |> add Candidate candidates
  |> drain ~is_key state
  |> add No_root (by_identifier allocated)
  |> drain ~is_key state

let blocks t = List.map snd (IntMap.bindings t.blocks)

let number t base = Base.Map.find_opt base t.numbers

(* ----- Rewriting -------------------------------------------------------- *)

let to_numbers t =
  let add n (base, weak, _) acc = (base, placeholder ~weak n) :: acc in
  Base.substitution_from_list (IntMap.fold add t.blocks [])

let of_numbers t =
  let add n (base, weak, _) acc = (placeholder ~weak n, base) :: acc in
  Base.substitution_from_list (IntMap.fold add t.blocks [])

type entry = {
  args: Cvalue.V.t Lattice_bounds.or_bottom list;
  key: Base.Hptset.t;
  start: Cvalue.Model.t * Locals_scoping.clobbered_set;
  exits: (Cvalue.Model.t * Locals_scoping.clobbered_set) list;
}

let rewrite_bases substitution bases =
  snd (Base.Hptset.replace substitution bases)

let rewrite_value substitution v =
  snd (Cvalue.V.replace_base substitution v)

(* The values first, then the bases bound: as the observer of the tests of
   the hit log renames a state. No two bases have the same image, and an
   image is not bound in the state, so that no offsetmaps are joined. *)
let rewrite_model substitution = function
  | Cvalue.Model.Map map ->
    let rewrite v =
      snd (Cvalue.V_Or_Uninitialized.replace_base substitution v)
    in
    Cvalue.Model.fold
      (fun base offsetmap acc ->
         Cvalue.Model.add_base base
           (Cvalue.V_Offsetmap.map_on_values rewrite offsetmap) acc)
      map Cvalue.Model.empty_map
    |> Cvalue.Model.replace_base substitution
  | (Cvalue.Model.Top | Cvalue.Model.Bottom) as model -> model

(* A new record: the clobbered set of a state is shared by every state of
   the call, and is not changed. *)
let rewrite_clobbered substitution { Locals_scoping.clob } =
  let clob =
    match clob with
    | Base.SetLattice.Top -> Base.SetLattice.top
    | Base.SetLattice.Set bases ->
      Base.SetLattice.inject (rewrite_bases substitution bases)
  in
  { Locals_scoping.clob }

let rewrite_state substitution (model, clobbered) =
  rewrite_model substitution model, rewrite_clobbered substitution clobbered

let rewrite substitution entry =
  let rewrite_argument = Lattice_bounds.Bottom.map (rewrite_value substitution)
  and rewrite_state = rewrite_state substitution in
  { args = List.map rewrite_argument entry.args;
    key = rewrite_bases substitution entry.key;
    start = rewrite_state entry.start;
    exits = List.map rewrite_state entry.exits; }

(* ----- Checks ----------------------------------------------------------- *)

let is_unnumbered base =
  is_allocated base && Option.is_none (placeholder_number base)

let unnumbered_of_bases bases = Base.Hptset.filter is_unnumbered bases

let unnumbered_of_value v =
  match Cvalue.V.get_bases v with
  | Base.SetLattice.Top -> Base.Hptset.empty
  | Base.SetLattice.Set bases -> unnumbered_of_bases bases

let unnumbered_of_state (model, { Locals_scoping.clob }) =
  let of_clobbered =
    match clob with
    | Base.SetLattice.Top -> Base.Hptset.empty
    | Base.SetLattice.Set bases -> unnumbered_of_bases bases
  in
  match model with
  | Cvalue.Model.Top | Cvalue.Model.Bottom -> of_clobbered
  | Cvalue.Model.Map map ->
    let add_value v acc =
      Base.Hptset.union
        (unnumbered_of_value (Cvalue.V_Or_Uninitialized.get_v v)) acc
    in
    Cvalue.Model.fold
      (fun base offsetmap acc ->
         let acc =
           if is_unnumbered base then Base.Hptset.add base acc else acc
         in
         Cvalue.V_Offsetmap.fold_on_values add_value offsetmap acc)
      map of_clobbered

let unnumbered entry =
  let of_argument = function
    | `Bottom -> Base.Hptset.empty
    | `Value v -> unnumbered_of_value v
  in
  List.fold_left Base.Hptset.union (unnumbered_of_bases entry.key)
    (List.map of_argument entry.args
     @ List.map unnumbered_of_state (entry.start :: entry.exits))

type error =
  | Unknown
  | Unnumbered of Base.Hptset.t

let number_entry ~candidates entry =
  match
    of_entry ~candidates ~args:entry.args ~key:entry.key (fst entry.start)
  with
  | exception Unknown_targets -> Error Unknown
  | t ->
    let numbered = rewrite (to_numbers t) entry in
    let left = unnumbered numbered in
    if Base.Hptset.is_empty left then Ok (t, numbered)
    else Error (Unnumbered left)

let equal_argument a b =
  match a, b with
  | `Bottom, `Bottom -> true
  | `Value a, `Value b -> Cvalue.V.equal a b
  | (`Bottom | `Value _), _ -> false

let equal_state (m1, c1) (m2, c2) =
  Cvalue.Model.equal m1 m2
  && Base.SetLattice.equal c1.Locals_scoping.clob c2.Locals_scoping.clob

let equal_entry e1 e2 =
  List.equal equal_argument e1.args e2.args
  && Base.Hptset.equal e1.key e2.key
  && equal_state e1.start e2.start
  && List.equal equal_state e1.exits e2.exits
