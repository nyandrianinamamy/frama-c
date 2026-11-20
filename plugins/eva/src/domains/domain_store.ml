(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval

type control_point =
  | Initial
  | Start of Kernel_function.t
  | Before of Cil_datatype.Stmt.t
  | After of Cil_datatype.Stmt.t
[@@deriving eq, ord]

module ControlPointPrototype = struct
  include Datatype.Serializable_undefined
  type t = control_point [@@deriving eq, ord]
  let name = "Domain_store.ControlPoint"
  let reprs = [ Initial ]

  let hash = function
    | Initial -> Hashtbl.hash 0
    | Start kf -> Hashtbl.hash (1, Kernel_function.hash kf)
    | Before stmt -> Hashtbl.hash (2, Cil_datatype.Stmt.hash stmt)
    | After stmt -> Hashtbl.hash (3, Cil_datatype.Stmt.hash stmt)

  let pretty fmt = function
    | Initial -> Format.fprintf fmt "Initial"
    | Start kf -> Format.fprintf fmt "Start of %a" Kernel_function.pretty kf
    | Before stmt -> Format.fprintf fmt "Before %a" Printer.pp_stmt stmt
    | After stmt -> Format.fprintf fmt "After %a" Printer.pp_stmt stmt
end

module ControlPoint = Datatype.Make_with_collections (ControlPointPrototype)

let line stmt = Fileloc.line (Cil_datatype.Stmt.loc stmt)

(* Same naming as the acceptance driver: entry point, then callee@line. *)
let pretty_callstack fmt callstack =
  let pp_call fmt (kf, kinstr) =
    match kinstr with
    | Cil_types.Kglobal -> ()
    | Kstmt stmt ->
      Format.fprintf fmt "/%a@%d" Kernel_function.pretty kf (line stmt)
  in
  Format.fprintf fmt "%a%a"
    Kernel_function.pretty callstack.Callstack.entry_point
    (Pretty_utils.pp_list ~sep:"" pp_call)
    (Callstack.to_call_list callstack)

(* Short description of a read point for {!Legacy_read_guard}. *)
let pretty_read_point ?callstack control_point fmt =
  let kf stmt = Kernel_function.find_englobing_kf stmt in
  begin match control_point with
    | Initial -> Format.pp_print_string fmt "initial state"
    | Start kf -> Format.fprintf fmt "start of %a" Kernel_function.pretty kf
    | Before stmt ->
      Format.fprintf fmt "before line %d of %a" (line stmt)
        Kernel_function.pretty (kf stmt)
    | After stmt ->
      Format.fprintf fmt "after line %d of %a" (line stmt)
        Kernel_function.pretty (kf stmt)
  end;
  Option.iter (Format.fprintf fmt " in %a" pretty_callstack) callstack


module type InputDomain = sig
  include Datatype.S
  val name: string
  val top: t
end

module type S = sig
  type t
  val set_state: ?callstack:Callstack.t -> control_point -> t -> unit
  val get_state: ?callstack:Callstack.t -> control_point -> t or_top_bottom
  val callstacks: control_point -> Callstack.t list or_top
  val is_computed: unit -> bool
end

module Make (Domain: InputDomain) = struct

  let dname = Domain.name ^ ": " ^ Domain.datatype_name

  let info name : (module State_builder.Info_with_size) =
    (module struct
      let name = Format.asprintf "Eva.Domain_store.Make(%s).%s" dname name
      let size = 17
      let dependencies = [ Self.state ]
    end)

  (* Are states of this domain saved? *)
  module Save = State_builder.Option_ref (Datatype.Bool) (val info "Save")

  (* If the domain is unmarshable, its states cannot be saved on the disk,
     so this boolean should be saved as false. *)
  let () =
    if Descr.is_unmarshable Domain.datatype_descr
    then
      let marshal b =
        if b then
          Self.warning "Cannot save states of %s domain on disk." Domain.name;
        false
      in
      Save.howto_marshal (fun r -> Option.map marshal !r) (ref)

  module Table =
    State_builder.Hashtbl (ControlPoint.Hashtbl) (Domain) (val info "Table")

  module States_by_callstack = Callstack.Hashtbl.Make (Domain)

  module TableByCallstack =
    State_builder.Hashtbl
      (ControlPoint.Hashtbl) (States_by_callstack) (val info "TableByCallstack")

  let save () =
    Parameters.(ResultsAll.get () && not (NoResultsDomain.mem Domain.name))

  let set_state ?callstack control_point state =
    if Save.memo save then
      match callstack with
      | None -> Table.replace control_point state
      | Some callstack ->
        let create _key = Callstack.Hashtbl.create 7 in
        let by_callstack = TableByCallstack.memo create control_point in
        Callstack.Hashtbl.replace by_callstack callstack state

  let notify access ?callstack control_point =
    Legacy_read_guard.notify access ~store:Domain.name
      (pretty_read_point ?callstack control_point)

  let computed () = Save.get_option () |> Option.value ~default:false

  let is_computed () =
    Legacy_read_guard.notify Availability ~store:Domain.name
      (fun fmt -> Format.pp_print_string fmt "recorded states");
    computed ()

  let get_state ?callstack control_point =
    notify Getter ?callstack control_point;
    if computed ()
    then
      try
        match callstack with
        | None -> `Value (Table.find control_point)
        | Some callstack ->
          let cs_tbl = TableByCallstack.find control_point in
          `Value (Callstack.Hashtbl.find cs_tbl callstack)
      with Not_found -> `Bottom
    else `Top

  let get_callstacks key =
    TableByCallstack.find key |> Callstack.Hashtbl.to_seq_keys |> List.of_seq

  let callstacks control_point =
    notify Enumeration control_point;
    if computed () then
      try `Value (get_callstacks control_point)
      with Not_found -> `Value []
    else `Top
end
