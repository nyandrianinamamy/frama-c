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

let pretty_point fmt point =
  let pretty_stmt position stmt =
    Format.fprintf fmt "%s %a in %a" position
      Fileloc.pretty (Cil_datatype.Stmt.loc stmt)
      Kernel_function.pretty (Kernel_function.find_englobing_kf stmt)
  in
  match point with
  | Initial -> Format.pp_print_string fmt "initial state"
  | Start kf -> Format.fprintf fmt "start of %a" Kernel_function.pretty kf
  | Before stmt -> pretty_stmt "before" stmt
  | After stmt -> pretty_stmt "after" stmt


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

  let is_computed () = Save.get_option () |> Option.value ~default:false

  (* Signals a read of the tables to the test instrument. *)
  let signal access control_point =
    Legacy_read_trap.read ~store:Domain.name access
      (fun fmt -> pretty_point fmt control_point)

  let get_state ?callstack control_point =
    if Legacy_read_trap.reading () then begin
      let access =
        match callstack with
        | None -> Legacy_read_trap.Joined
        | Some callstack -> Legacy_read_trap.Callstack callstack
      in
      signal access control_point
    end;
    if is_computed ()
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
    if Legacy_read_trap.reading () then signal Callstacks control_point;
    if is_computed () then
      try `Value (get_callstacks control_point)
      with Not_found -> `Value []
    else `Top
end
