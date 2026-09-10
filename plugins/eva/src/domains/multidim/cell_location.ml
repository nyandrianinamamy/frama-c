(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval
open Lattice_bounds

module Offset = Abstract_offset
module Bases = Base.Base.Map
module References = Cil_datatype.Varinfo.Set
module Prototype = Bases.Make (Top.Make_Datatype (Offset))
include Datatype.With_collections (Prototype)
include Prototype

type oracle = Cell_oracle.oracle
type offset = Offset.t or_top
type base = Base.t

let empty : t = Bases.empty

let singleton base offset : t =
  Bases.singleton base (`Value offset)

let fold (f : base -> offset -> 'a -> 'a) (loc : t) (acc : 'a) : 'a =
  Bases.fold f loc acc

let bases (loc : t) =
  Bases.fold (fun b _ acc -> b :: acc) loc []

let to_singleton loc =
  let aux base off = function None -> Some (base, off) | Some _ -> raise Exit in
  try fold aux loc None with Exit -> None

let is_singleton ~oracle loc =
  let oracle = Cell_oracle.convert_oracle oracle in
  match to_singleton loc with
  | None | Some (_, `Top) -> false
  | Some (b, `Value o) -> not (Base.is_weak b) && Offset.is_singleton ~oracle o

let to_singleton_var loc =
  match to_singleton loc with
  | Some (Var (vi, _), `Value (NoOffset t)) -> (* maybe too restrictive *)
    if Typed_memory.are_typ_compatible vi.vtype t then Some vi else None
  | _ -> None

let references (loc : t) =
  let union o = References.union (Offset.references o) in
  let add_ref _ = function `Top -> Fun.id | `Value o -> union o in
  fold add_ref loc References.empty |> References.elements

let of_var vi =
  singleton (Base.of_varinfo vi) (Offset.of_var_address vi)

let add_index ~oracle index offset =
  match index with
  | None -> `Value offset
  | Some exp -> Offset.add_index ~oracle offset exp

let append_offset ~oracle (exp : exp) index offset base ival =
  let open Top.Operators in
  let* base_typ = Base.typeof base |> Top.of_option in
  let typ = Ast_types.C.direct_pointed exp.typ in
  let* base_offset = Offset.of_ival ~base_typ ~typ ival in
  let* base_offset = add_index ~oracle index base_offset in
  let+ offset in Offset.append base_offset offset

let extract_index (exp : exp) =
  match exp.node with
  | BinOp (PlusPI, e1, e2, _) -> e1, Some e2
  | _ -> exp, None

let of_lval ~oracle:cvalue_oracle (lval : lval) : t or_top =
  let oracle = Cell_oracle.convert_oracle cvalue_oracle in
  let host, offset = lval.node in
  let base_typ = Eva_ast.type_of_lhost host in
  let offset = Offset.of_eva_offset ~oracle base_typ offset in
  match host with
  | Var vi -> `Value (Bases.singleton (Base.of_varinfo vi) offset)
  | Mem exp ->
    let exp, index = extract_index exp in
    let append = append_offset ~oracle exp index offset in
    let add base ival = Bases.add base (append base ival) in
    let bits = Addresses.Bits.of_bytes (cvalue_oracle exp) in
    try `Value (Addresses.Bits.fold_topset_ok add bits empty)
    with Abstract_interp.Error_Top -> `Top

let var_of_term_host env = function
  | Cil_types.TVar { lv_origin = Some vi } -> `Value vi
  | TResult _ -> Top.of_option env.Abstract_domain.result
  | _ -> `Top

let of_term_lval env ((lhost, offset) as lval) =
  let open Top.Operators in
  let+ vi = var_of_term_host env lhost in
  let base = Base.of_varinfo vi in
  let offset = Offset.of_term_offset vi.vtype offset in
  Bases.singleton base offset, Cil.typeOfTermLval lval

let of_term env (t : Cil_types.term) =
  match t.term_node with
  | TLval term_lval -> of_term_lval env term_lval
  | _ -> `Top

let of_precise_loc ploc : t =
  let Locations.{ addr ; _ } = Precise_locs.imprecise_location ploc in
  let typeof b = Option.value ~default:Cil_const.voidType (Base.typeof b) in
  let add base = Bases.add base (`Value (Offset.NoOffset (typeof base))) in
  Addresses.Bits.fold_bases add addr empty
