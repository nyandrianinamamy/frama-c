(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* --- Threads definition --- *)

(* This type only defines immutable properties of threads and is enough
   to print a human-readable description of the thread. *)
type kind =
  | Main
  | InterruptHandler of Kernel_function.t
  | Thread of Concurrency.Name.t option

module Data = struct
  type t = kind
  let name = "thread"
  let array_of_ids = Mt_lib.array_threads

  let reprs =
    List.map (fun kf -> InterruptHandler kf) Kernel_function.reprs @
    List.map (fun name -> Thread (Some name)) Concurrency.Name.reprs

  let pretty fmt (kind, id) =
    match kind with
    | Thread Some name -> Concurrency.Name.pretty fmt name
    | Thread None -> Format.fprintf fmt "#%i" id
    | Main -> Format.fprintf fmt "<main>"
    | InterruptHandler kf ->
      Format.fprintf fmt "<interrupt_handler %a>" Kernel_function.pretty kf
end

(* The identity of a thread is used to choose whether to group thread
   analyses or not. If two spawned threads share the same identity, they
   will be handled in the same analysis. *)
module Identity = struct

  type key =
    | ByName of Concurrency.Name.t
    | BySpawnPoint of Position.Local.t
    | ByInterruptHandler of Kernel_function.t
  [@@deriving eq, ord]

  type t = { key: key; entry_point: Kernel_function.t; } [@@deriving eq, ord]

  let key_reprs =
    List.map (fun name -> ByName name) Concurrency.Name.reprs @
    List.map (fun pos -> BySpawnPoint pos) Position.Local.reprs @
    List.map (fun kf -> ByInterruptHandler kf) Kernel_function.reprs

  let reprs =
    List.product_map
      (fun key entry_point -> { key; entry_point })
      key_reprs Kernel_function.reprs

  let hash_key = function
    | ByName name -> Hashtbl.hash (1, Concurrency.Name.hash name)
    | BySpawnPoint al -> Hashtbl.hash (2, Position.Local.hash al)
    | ByInterruptHandler kf -> Hashtbl.hash (3, Kernel_function.hash kf)

  let hash { key; entry_point } =
    Hashtbl.hash (hash_key key, Kernel_function.hash entry_point)
end

include Mt_ids.Make (Identity) (Data)

let main = create_global Main
let is_main = equal main
let main_id = id main

let from_callstack cs =
  match find cs.Callstack.thread with
  | Some th -> th
  | None ->
    Self.fatal
      "The thread id (%d) in the considered callstack does not match any \
       existing thread"
      cs.thread

let from_local_position pos =
  Position.Local.callstack pos
  |> from_callstack

let from_position pos =
  Position.callstack pos
  (* The only position that do not have a callstack associated is GlobalInit.
     The global variables initialization are done by the main thread. *)
  |> Option.fold ~some:from_callstack ~none:main

(* --- Thread state --- *)

(* The thread state is all the information learned about the threads during
   the analysis *)

module PosSet = Position.Local.Set
module Varinfo = Cil_datatype.Varinfo

type properties = {
  entry_point : Kernel_function.t;
  spawn_points : PosSet.t;
  arguments : (Varinfo.t * Cvalue.V.t) list;
}

module Properties =
struct
  module Prototype =
  struct
    include Datatype.Serializable_undefined

    type t = properties

    let name = "Eva.Thread.Properties"

    let reprs = [{
        entry_point = List.hd Kernel_function.reprs;
        spawn_points = List.hd PosSet.reprs;
        arguments = [List.hd Varinfo.reprs, List.hd Cvalue.V.reprs];
      }]

    let structural_descr =
      let tuple_list t = Structural_descr.(t_tuple t |> t_list |> pack) in
      Structural_descr.t_record [|
        Kernel_function.packed_descr;
        PosSet.packed_descr;
        tuple_list [| Varinfo.packed_descr; Cvalue.V.packed_descr |];
      |]

    let pretty fmt properties =
      let spawn_points = PosSet.elements properties.spawn_points in
      let pp_sep fmt () = Format.fprintf fmt ";@ " in
      let pp_var = Varinfo.pretty in
      let pp_val = Cvalue.V.pretty in
      let pp_al = Position.Local.pretty in
      let pp_arg fmt (vi, v) = Format.fprintf fmt "%a: %a" pp_var vi pp_val v in
      Format.fprintf fmt
        "@[<v 2>Entry point  :@ @[<hov>%a@]@]@\n\
         @[<v 2>Spawn points :@ @[<hov>%a@]@]@\n\
         @[<v 2>Arguments    :@ @[<hov>%a@]@]"
        Kernel_function.pretty properties.entry_point
        Format.(pp_print_list ~pp_sep pp_al) spawn_points
        Format.(pp_print_list ~pp_sep pp_arg) properties.arguments
  end

  include Prototype
  include Datatype.Make (Prototype)

  (* Combine a list of arguments with their formal parameters; used
     for arguments value storage *)
  let map_arguments kf args =
    let formals = Kernel_function.get_formals kf in
    try
      List.combine formals args
    with Invalid_argument _ ->
      Self.abort
        "Arguments mismatch in thread creation; function %s expected %d \
         arguments, but %d were given"
        (Kernel_function.get_name kf) (List.length formals) (List.length args)

  let create spawn_point entry_point arguments =
    {
      entry_point;
      spawn_points = PosSet.singleton spawn_point;
      arguments = map_arguments entry_point arguments
    }

  let main_properties () =
    {
      entry_point = Globals.entry_point () |> fst;
      spawn_points = PosSet.empty;
      arguments = [];
    }

  let interrupt_properties kf =
    {
      entry_point = kf;
      spawn_points = PosSet.empty;
      arguments = [];
    }

  let add properties spawn_point entry_point arguments =
    assert (Kernel_function.equal entry_point properties.entry_point);
    {
      entry_point;
      spawn_points = PosSet.add spawn_point properties.spawn_points;
      arguments =
        (* Join a thread argument as varinfo * cvalue with a new cvalue *)
        let join_argument (vi, v1) v2 = (vi, Cvalue.V.join v1 v2) in
        try List.map2 join_argument properties.arguments arguments
        with Invalid_argument _ ->
          Self.abort ~current:true
            "Trying to spawn a thread with %d arguments when it was \
             already spawned with %d"
            (List.length arguments)
            (List.length properties.arguments)
    }

end

module State = State_builder.Hashtbl (Hashtbl) (Properties)
    (struct
      let name = "Eva.Thread.State"
      let dependencies = []
      let size = 13
    end)

let clear () = clear (); State.clear ()


let spawn spawn_point name entry_point arguments =
  let key = match name with
    | Some name -> Identity.ByName name
    | None -> BySpawnPoint spawn_point
  in
  let identity = Identity.{ key; entry_point } in
  let kind = Thread name in
  let th = create identity kind in
  let properties = match State.find_opt th with
    (* The thread identity is new; register this thread *)
    | None ->
      Properties.create spawn_point entry_point arguments
    (* The thread identity has been found; join the thread properties *)
    | Some properties ->
      Properties.add properties spawn_point entry_point arguments
  in
  State.replace th properties;
  th

let is_interrupt_handler entry_point =
  let key = Identity.ByInterruptHandler entry_point in
  mem_identity Identity.{ key; entry_point }

let interrupt_handler entry_point =
  let key = Identity.ByInterruptHandler entry_point in
  let identity = Identity.{ key; entry_point } in
  let kind = InterruptHandler entry_point in
  create identity kind

let interrupt_handlers () =
  fold_identity
    (fun _ th handlers ->
       match get th with
       | InterruptHandler _ -> th :: handlers
       | Thread _ | Main -> handlers)
    []

let register_interrupt_handlers kfs =
  Kernel_function.Set.iter
    (fun kf -> interrupt_handler kf |> ignore)
    kfs

let properties thread =
  match get thread with
  | Main -> Properties.main_properties ()
  | InterruptHandler kf -> Properties.interrupt_properties kf
  | Thread _ -> State.find thread

let entry_point th =
  (properties th).entry_point
