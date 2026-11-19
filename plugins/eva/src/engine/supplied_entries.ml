(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Entry = Cache_entry.Cvalue

type entry = Entry.t

type footprint = Cache_entry.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

module Entries =
  Datatype.Make
    (struct
      include Datatype.Undefined
      type t = Entry.t list
      let name = "Eva.Supplied_entries.Entries"
      let reprs = [ [] ]
      let mem_project = Datatype.never_any_project
    end)

(* Entries supplied for each function, oldest first. *)
module Table =
  Kernel_function.Make_Table
    (Eva_utils.Do_Not_Marshal (Entries))
    (struct
      let size = 7
      let dependencies = [ Ast.self ]
      let name = "Eva.Supplied_entries.Table"
    end)

module Counter =
  State_builder.Counter (struct let name = "Eva.Supplied_entries.Counter" end)

let entries kf = Option.value ~default:[] (Table.find_opt kf)

(* The clobbered set of a state: the blocks bound in [model] that may hold
   the address of a local or formal variable. *)
let holders model =
  match model with
  | Cvalue.Model.Top -> Locals_scoping.top ()
  | Bottom -> Locals_scoping.bottom ()
  | Map m ->
    let add b offsetmap acc =
      if Locals_scoping.offsetmap_contains_local offsetmap
      then Base.Hptset.add b acc
      else acc
    in
    let clob = Locals_scoping.bottom () in
    let bases = Cvalue.Model.fold add m Base.Hptset.empty in
    Locals_scoping.remember_bases_with_locals clob
      (Base.SetLattice.inject bases);
    clob

(* Whether block [b] exists at the exit of the body of [kf]: all blocks do
   but the locals of its inner blocks, which leave their scope before. *)
let exists_at_exit kf b =
  match b with
  | Base.Var (vi, _) when Kernel_function.is_local vi kf ->
    let fundec = Kernel_function.get_definition kf in
    List.exists (Cil_datatype.Varinfo.equal vi) fundec.sbody.blocals
  | _ -> true

(* [model] is a map: [supply] refuses Top and Bottom exit states. *)
let binds model b =
  match Cvalue.Model.find_base b model with
  | _ -> true
  | exception Not_found -> false

(* [reuse] on cvalue keeps the value of the input for a block of W_exit that
   the exit state does not bind: each exit state must bind every block of
   W_exit that exists at the exit. *)
let check_exit kf entry =
  let check (_, (model, _)) b =
    if exists_at_exit kf b && not (binds model b) then
      Format.kasprintf invalid_arg
        "Supplied_entries.supply: an exit state does not bind the block %a, \
         written on a path to an exit" Base.pretty b
  in
  let written = (Entry.footprint entry).written_exit in
  List.iter (fun s -> Base.Hptset.iter (check s) written) (Entry.exit entry)

let check_exit_state (_, model) =
  if Cvalue.Model.is_top model then
    invalid_arg "Supplied_entries.supply: an exit state is Top";
  if not (Cvalue.Model.is_reachable model) then
    invalid_arg
      "Supplied_entries.supply: an exit state is Bottom; a body that never \
       returns has no exit state"

let add kf entry =
  ignore (Counter.next ());
  Table.replace kf (entries kf @ [ entry ]);
  entry

let supply kf ~key ~input ~footprint ~exit =
  (* A call whose input is [Top] would match an entry whose input is [Top],
     and [reuse] would then return the exit state alone, without the blocks
     of the caller. No call is analysed from [Bottom]. *)
  if not (Cvalue.Model.is_reachable input) || Cvalue.Model.is_top input then
    invalid_arg "Supplied_entries.supply: the input is Top or Bottom";
  (* [reuse] of a Top exit state is Top, which loses the blocks of the
     caller. An exit state that is Bottom describes no execution. *)
  List.iter check_exit_state exit;
  let exit = List.map (fun (k, s) -> k, (s, holders s)) exit in
  let input = input, Locals_scoping.bottom () in
  let id = Counter.get () + 1 in
  let entry = Entry.make ~id (Body kf) ~key ~input ~footprint ~exit in
  check_exit kf entry;
  add kf entry

let supply_produced produced =
  let entry = Cache_producer.cache_entry produced in
  let Cache_entry.Body kf = Entry.statement entry in
  add kf (Entry.with_id (Counter.get () + 1) entry)

let empty_key = Partition.Key.empty

let case_key kf rank =
  let stmt = Kernel_function.find_return kf in
  Partition.(Key.add_branch (Disjunction_case { stmt; rank }) Key.empty)

let return_variable = Library_functions.get_retres_vi

let clear () = Table.clear ()

(* Whether the current analysis uses the supplied entries. It is decided when
   the analysis starts, so that no analysis has both caches. *)
module Active =
  State_builder.Ref (Datatype.Bool)
    (struct
      let name = "Eva.Supplied_entries.Active"
      let dependencies = [ Ast.self ]
      let default () = false
    end)

let () =
  Cvalue_callbacks.register_at_start_hook
    (fun () -> Active.set (Table.length () > 0))

let active = Active.get

let id = Entry.id
let statement = Entry.statement
let key = Entry.key
let input e = fst (Entry.input e)
let footprint = Entry.footprint
let exit e = List.map (fun (k, (s, _)) -> k, s) (Entry.exit e)
let pretty = Entry.pretty

type rejection = [ Cache_entry.rejection | `Product | `Consumer ]

let rejections : rejection list =
  [ `Key_differs; `Key_unclosed; `Sweep; `Recursion; `Hint_generation;
    `Watchpoint; `Automatic_cleanup; `Product; `Consumer ]

let rejection_id : rejection -> string = function
  | #Cache_entry.rejection as r -> Cache_entry.rejection_id r
  | `Product -> "product"
  | `Consumer -> "consumer"

type 'state lookup = {
  rejected : (int * rejection) list;
  hit : (entry * (Partition.key * 'state) list) option;
}

(* Inout and From resolve the identifier given with [`Reuse] to the callbacks
   in their tables of memexec results, and so does the analysis of threads. *)
let consumer_enabled () =
  Plugin.is_present "inout" || Plugin.is_present "from"
  || Mt_options.Enabled.get ()

let cast : type a b. (a, b) Structure.eq -> a -> b = fun Structure.Eq x -> x
let cast_back : type a b. (a, b) Structure.eq -> b -> a =
  fun Structure.Eq x -> x

module Lookup (Domain : sig
    type t
    val structure : t Abstract.Domain.structure
  end) = struct

  (* An equality between the states of the active domains and those of the
     cvalue domain, if the active domains are the cvalue domain alone. *)
  let cvalue_alone : (Domain.t, Cvalue_domain.State.t) Structure.eq option =
    match Domain.structure with
    | Abstract.Domain.Leaf (key, _) ->
      Structure.Key_Domain.eq_type key Cvalue_domain.State.key
    | _ -> None

  let admit stack entry (model, _) =
    let dependencies = Entry.dependencies entry in
    let used_functions =
      Option.fold ~none:[] ~some:(fun d -> d.Cache_entry.used_functions)
        dependencies
    in
    let would_skip_cleanup (f, _) =
      not (Kernel_function.equal f (Callstack.top_kf stack))
      && Kernel_function.is_definition f
    in
    if Body_access.recursion_conflict stack used_functions then Error `Recursion
    else if List.exists would_skip_cleanup used_functions
         && Builtins_malloc.has_automatic_bases ()
    then Error `Automatic_cleanup
    else if Builtins_watchpoint.active () then Error `Watchpoint
    else
      match dependencies with
      | None -> Ok ()
      | Some d ->
        let stale g =
          not (Widen_generation.equal g (Widen_generation.current ()))
        in
        if Option.fold ~none:false ~some:stale d.hint_generation
        then Error `Hint_generation
        else if not (Sweep_access.clear_input d.sweeps model) then Error `Sweep
        else Ok ()

  let find stack state =
    match entries (Callstack.top_kf stack) with
    | [] -> { rejected = []; hit = None }
    | candidates ->
      let reject_all reason =
        let rejected = List.map (fun e -> Entry.id e, reason) candidates in
        { rejected; hit = None }
      in
      match cvalue_alone with
      | None -> reject_all `Product
      | Some _ when consumer_enabled () || stack.thread <> Thread.main_id ->
        reject_all `Consumer
      | Some eq ->
        let result = Entry.find ~admit:(admit stack) candidates (cast eq state) in
        let reject (e, reason) = Entry.id e, (reason :> rejection) in
        let hit (e, states) =
          e, List.map (fun (k, s) -> k, cast_back eq s) states
        in
        { rejected = List.map reject result.rejected;
          hit = Option.map hit result.hit }
end
