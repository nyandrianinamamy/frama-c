(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Entry = Cache_entry.Make (Cvalue_domain.State)

type entry = Entry.t

type footprint = Cache_entry.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
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

let supply kf ~key ~input ~footprint ~exit =
  let cvalue_state s = s, Locals_scoping.bottom () in
  let exit = List.map (fun s -> Partition.Key.empty, cvalue_state s) exit in
  let entry =
    Entry.make ~id:(Counter.next ()) (Body kf)
      ~key ~input:(cvalue_state input) ~footprint ~exit
  in
  Table.replace kf (entries kf @ [ entry ]);
  entry

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
  [ `Key_differs; `Key_unclosed; `Product; `Consumer ]

let rejection_id : rejection -> string = function
  | #Cache_entry.rejection as r -> Cache_entry.rejection_id r
  | `Product -> "product"
  | `Consumer -> "consumer"

type 'state lookup = {
  rejected : (int * rejection) list;
  hit : (int * (Partition.key * 'state) list) option;
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

  let find kf state =
    match entries kf with
    | [] -> { rejected = []; hit = None }
    | candidates ->
      let reject_all reason =
        let rejected = List.map (fun e -> Entry.id e, reason) candidates in
        { rejected; hit = None }
      in
      match cvalue_alone with
      | None -> reject_all `Product
      | Some _ when consumer_enabled () -> reject_all `Consumer
      | Some eq ->
        let result = Entry.find candidates (cast eq state) in
        let reject (e, reason) = Entry.id e, (reason :> rejection) in
        let hit (e, states) =
          Entry.id e, List.map (fun (k, s) -> k, cast_back eq s) states
        in
        { rejected = List.map reject result.rejected;
          hit = Option.map hit result.hit }
end
