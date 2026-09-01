(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type state = Mt_memory.Types.state
type value = Mt_memory.Types.value

module type Data = sig
  type t
  val repr : t
  val name : string
  val pretty : Format.formatter -> t * int -> unit
  val array_of_ids : unit -> Cil_types.varinfo
end

module type Identity = sig
  type t
  val repr : t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val hash : t -> int
end

module type S = sig
  include Datatype.S_with_collections
  val label : t -> string
  val id : t -> int
  val find : int -> t option

  val read_state : state -> t -> value
  val read_state_enumerate : int -> state -> t -> int list Mt_memory.conversion
  val write_state : state -> t -> int -> state
  val replace_value : state -> t -> before:int -> after:int -> state

  val clear : unit -> unit
end

module Make (Identity : Identity) (Data : Data) = struct

  module Prototype = struct
    include Datatype.Serializable_undefined
    type t = { id: int; data: Data.t }

    let name = "Mt_ids.Make(" ^ Data.name ^ ")"
    let reprs = [ { id = 0; data = Data.repr } ]
    let equal t1 t2 = Int.equal t1.id t2.id
    let compare t1 t2 = Int.compare t1.id t2.id
    let hash th = th.id
    let pretty fmt t = Data.pretty fmt (t.data, t.id)
  end

  module D = Datatype.Make_with_collections (Prototype)
  include D
  include Prototype

  let info name : (module State_builder.Info_with_size) =
    (module struct
      let name = datatype_name ^ "." ^ name
      let dependencies = []
      let size = 13
    end)

  module ById =
    State_builder.Hashtbl (Datatype.Int.Hashtbl) (D) (val info "ById")

  let last_id = ref 0
  let next_id () = incr last_id; !last_id

  let make data =
    let t = { id = next_id (); data } in
    ById.add t.id t;
    t

  let find = ById.find_opt

  let id t = t.id
  let get t = t.data
  let label = Pretty_utils.to_string pretty

  let pointer_of_id id : Mt_memory.Types.pointer =
    assert (id > 0);
    let array = Data.array_of_ids ()
    and offset = (id - 1) * (Machine.Sizeof.int ())
    (* Let us not lose the first cell of the array *)
    in
    array, offset

  let read_state state t =
    let p = pointer_of_id t.id in
    Mt_memory.read_int_pointer p state

  let read_state_enumerate cardinal state t =
    read_state state t |>
    Mt_memory.extract_int_list ~cardinal |>
    Result.map_error
      (fun s -> Format.asprintf "%s id %i contains %s" Data.name t.id s)

  let write_state state t v =
    let p = pointer_of_id t.id in
    Mt_memory.write_int_pointer p v state

  let replace_value state t ~before ~after =
    let p = pointer_of_id t.id in
    Mt_memory.replace_value_at_int_pointer p ~before ~after state

  (* --- Identity --- *)

  module Id_Prototype = struct
    include Datatype.Serializable_undefined
    include Identity
    let reprs = [ repr ]
    let name = "Eva." ^ Data.name ^ ".Identity"
  end
  module Id_Datatype = Datatype.Make_with_collections (Id_Prototype)

  module Identities =
    State_builder.Hashtbl (Id_Datatype.Hashtbl) (D) (val info "Identities")

  let create identity data =
    Identities.memo (fun _ -> make data) identity

  (* Values created with [create_global] always exist and should not be affected
     by function [clear] below. *)
  let global_values = ref []

  let create_global data =
    let t = make data in
    global_values := t :: !global_values;
    t

  let clear () =
    last_id := 0;
    ById.clear ();
    Identities.clear ();
    let reset t =
      last_id := max !last_id t.id;
      ById.add t.id t
    in
    List.iter reset !global_values

  let mem_identity = Identities.mem
  let fold_identity = Identities.fold
end
