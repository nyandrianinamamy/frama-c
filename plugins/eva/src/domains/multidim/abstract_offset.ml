(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Lattice_bounds
open Top.Operators

type offset =
  | NoOffset of Cil_types.typ
  | Index of Eva_ast.exp * Eva_ast.exp * Cil_types.typ * offset
  | Field of Cil_types.fieldinfo * offset

let rec pretty fmt = function
  | NoOffset _t -> ()
  | Field (fi, s) -> Format.fprintf fmt ".%s%a" fi.fname pretty s
  | Index (l, u, _t, s) ->
    if Eva_ast.Exp.equal l u then
      Format.fprintf fmt "[%a]%a"
        Eva_ast.Exp.pretty l
        pretty s
    else
      Format.fprintf fmt "[%a..%a]%a"
        Eva_ast.Exp.pretty l
        Eva_ast.Exp.pretty u
        pretty s

let ( <?> ) a b = if a = 0 then Lazy.force b else a

let rec compare t t' =
  match t, t' with
  | NoOffset t, NoOffset t' -> Cil_datatype.Typ.compare t t'
  | NoOffset _, (Index _ | Field _) -> -1
  | (Index _ | Field _), NoOffset _ ->  1
  | Field (fi, s), Field (fi', s') ->
    Cil_datatype.Fieldinfo.compare fi fi' <?> lazy (compare s s')
  | Field _, Index _ -> -1
  | Index _, Field _ ->  1
  | Index (l, u, t, s), Index (l', u', t', s') ->
    Cil_datatype.Typ.compare t t' <?>
    lazy (Eva_ast.Exp.compare l l') <?>
    lazy (Eva_ast.Exp.compare u u') <?>
    lazy (compare s s')

let rec hash = function
  | NoOffset t ->
    Cil_datatype.Typ.hash t
  | Field (fi, offset) ->
    let fi = Cil_datatype.Fieldinfo.hash fi in
    let offset = hash offset in
    Hashtbl.hash (fi, offset)
  | Index (l, u, t, offset) ->
    let l = Eva_ast.Exp.hash l in
    let u = Eva_ast.Exp.hash u in
    let t = Cil_datatype.Typ.hash t in
    let offset = hash offset in
    Hashtbl.hash (l, u, t, offset)

let structural_descr =
  let open Structural_descr in
  let r = Recursive.create () in
  let typ = Cil_datatype.Typ.packed_descr in
  let fi = Cil_datatype.Fieldinfo.packed_descr in
  let exp = Eva_ast.Exp.packed_descr in
  let no_offset = [| typ |] in
  let index = [| exp ; exp ;  typ ; recursive_pack r |] in
  let field = [| fi ; recursive_pack r |] in
  let descr = t_sum [| no_offset ; index ; field |] in
  Recursive.update r descr;
  descr

include Datatype.Make_with_collections
    (struct
      type t = offset
      let reprs = [ NoOffset (List.hd Cil_datatype.Typ.reprs) ]
      let structural_descr = structural_descr
      let name = "Eva.Multidim.Abstract_offset"
      let hash = hash
      let pretty = pretty
      let compare = compare
      let equal = Datatype.from_compare
      let copy = Datatype.undefined
      let rehash = Datatype.identity
      let mem_project = Datatype.never_any_project
    end)

let rec append o1 o2 =
  match o1 with
  | NoOffset _t -> o2
  | Field (fi, s) -> Field (fi, append s o2)
  | Index (l, u, t, s) -> Index (l, u, t, append s o2)

let add_index ~oracle base exp =
  let rec aux = function
    | NoOffset _ as o ->
      let idx = oracle exp in
      if Int_val.is_zero idx
      then `Value o
      else `Top (* Can't add index if not an array *)
    | Field (fi, sub) ->
      let+ sub' = aux sub in
      Field (fi, sub')
    | Index (l, u, t, (NoOffset _ as sub)) ->
      let l' = Eva_ast.Build.add l exp
      and u' = Eva_ast.Build.add u exp in
      (* TODO: is the new range inside bounds ? *)
      `Value (Index (l', u', t, sub))
    | Index (l, u, t, sub) ->
      let+ sub' = aux sub in
      Index (l, u, t, sub')
  in
  aux base

(* Unused function. *)
let rec _join o1 o2 =
  match o1, o2 with
  | NoOffset t, NoOffset t'
    when Bit_utils.type_compatible t t' ->
    `Value (NoOffset t)
  | Field (fi, sub1), Field (fi', sub2)
    when Cil_datatype.Fieldinfo.equal fi fi' ->
    let+ sub' = _join sub1 sub2 in
    Field (fi, sub')
  | Index (l1, u1, t1, sub1), Index (l2, u2, t2, sub2)
    when Bit_utils.type_compatible t1 t2 ->
    let+ l = if Eva_ast.Exp.equal l1 l2 then `Value l1 else `Top
    and+ u = if Eva_ast.Exp.equal u1 u2 then `Value u1 else `Top
    and+ sub = _join sub1 sub2 in
    Index (l, u, t1, sub)
  | _ -> `Top

let array_bounds array_size =
  (* TODO: handle undefined sizes and not const foldable sizes *)
  match array_size with
  | None -> None
  | Some size_exp ->
    match Cil.constFoldToInt size_exp with
    | None -> None
    | Some size when Z.gt size 0z -> Some (0z, Z.pred size)
    | Some _ -> None

let array_range array_size =
  Option.map
    (fun (l,u) -> Int_val.inject_range (Some l) (Some u))
    (array_bounds array_size)

let assert_valid_index idx size =
  match array_range size with
  | Some range when Int_val.is_included idx range -> `Value ()
  | _ -> `Top

let of_var_address vi =
  NoOffset vi.Cil_types.vtype

let rec of_eva_offset ~(oracle : Eva_ast.exp -> Int_val.t) base_typ = function
  | Eva_ast.NoOffset -> `Value (NoOffset base_typ)
  | Field (fi, sub) ->
    if Ast_types.C.has_qualifier "volatile" fi.ftype then
      `Top
    else
      let+ sub' = of_eva_offset ~oracle fi.ftype sub in
      Field (fi, sub')
  | Index (exp, sub) ->
    match Ast_types.C.unroll_node base_typ with
    | TArray (elem_typ, array_size) ->
      let idx = oracle exp in
      let+ () = assert_valid_index idx array_size
      and+ sub' = of_eva_offset ~oracle elem_typ sub in
      Index (exp, exp, elem_typ, sub')
    | _ -> assert false

let rec of_int_val ~base_typ ~typ ival =
  if Int_val.is_zero ival && Bit_utils.type_compatible base_typ typ then
    `Value (NoOffset typ)
  else
    match Ast_types.C.unroll_node base_typ with
    | TArray (elem_typ, array_size) ->
      let* range, rem =
        try
          let elem_size = Z.of_int (Cil.bitsSizeOf elem_typ) in
          if Z.is_zero elem_size then (* array of elements of size 0 *)
            if Int_val.is_zero ival then (* the whole range is valid *)
              let+ range = Top.of_option (array_range array_size) in
              range, ival
            else (* Non-zero offset cannot represent anything here *)
              `Top
          else
            let range = Int_val.scale_div ~pos:true elem_size ival
            and rem = Int_val.scale_rem ~pos:true elem_size ival in
            `Value (range, rem)
        with Cil.SizeOfError (_,_) ->
          (* Cil.bitsSizeOf can raise an exception when elements are
              themselves array of execution-time size *)
          if Int_val.is_zero ival then
            `Value (ival, ival)
          else
            `Top
      in
      let* () = assert_valid_index range array_size
      and* sub' = of_int_val ~base_typ:elem_typ ~typ rem in
      let l, u = Int_val.min_and_max range in
      let+ l = Top.of_option l and+ u = Top.of_option u in
      Index (Eva_ast.Build.integer l, Eva_ast.Build.integer u, elem_typ, sub')

    | TComp ci ->
      if not ci.cstruct then
        (* Ignore unions for now *)
        `Top
      else
        let rec find_field = function
          | [] -> `Top
          | fi :: q ->
            let offset, width = Cil.fieldBitsOffset fi in
            let l = Z.(of_int offset) in
            let u = Z.(pred (add l (of_int width))) in
            let matches =
              if width = 0 then
                Int_val.(equal ival (inject_singleton l))
              else
                let range = Int_val.inject_range (Some l) (Some u) in
                Int_val.is_included ival range
            in
            if matches then
              if Ast_types.C.has_qualifier "volatile" fi.ftype then
                `Top
              else
                let sub_ival = Int_val.add_singleton (Z.neg l) ival in
                let+ sub' = of_int_val ~base_typ:fi.ftype ~typ sub_ival in
                Field (fi, sub')
            else
              find_field q
        in
        find_field (Option.value ~default:[] ci.cfields)

    | _ -> `Top

let of_ival ~base_typ ~typ ival =
  match Ival.project_int_val ival with
  | Some ival -> of_int_val ~base_typ ~typ ival
  | None -> `Top

let index_of_term array_size t = (* Exact constant ranges *)
  match t.Cil_types.term_node with
  | TConst (Integer (v, _)) -> `Value (Int_val.inject_singleton v)
  | Trange (l,u) ->
    let eval bound = function
      | None -> Top.of_option bound
      | Some { Cil_types.term_node=TConst (Integer (v, _)) } -> `Value v
      | Some _ -> `Top
    in
    let bounds = array_bounds array_size in
    let lb = Option.map fst bounds and ub = Option.map snd bounds in
    let+ l' = eval lb l and+ u' = eval ub u in
    Int_val.inject_range (Some l') (Some u')
  | _ -> `Top

let rec of_term_offset base_typ = function
  | Cil_types.TNoOffset -> `Value (NoOffset base_typ)
  | TField (fi, sub) ->
    if Ast_types.C.has_qualifier "volatile" fi.ftype then
      `Top
    else
      let+ sub' = of_term_offset fi.ftype sub in
      Field (fi, sub')
  | TIndex (index, sub) ->
    begin match Ast_types.C.unroll_node base_typ with
      | TArray (elem_typ, array_size) ->
        let* idx = index_of_term array_size index in
        let* () = assert_valid_index idx array_size
        and* sub' = of_term_offset elem_typ sub in
        let l, u = Int_val.min_and_max idx in
        let+ l = Top.of_option l and+ u = Top.of_option u in
        Index (Eva_ast.Build.integer l, Eva_ast.Build.integer u, elem_typ, sub')
      | _ -> assert false
    end
  | _ -> `Top

let rec is_singleton ~(oracle : Eva_ast.exp -> Int_val.t) = function
  | NoOffset _ -> true
  | Field (_fi, sub) -> is_singleton ~oracle sub
  | Index (l, u, _elem_typ, sub) ->
    (Eva_ast.Exp.equal l u
     || (oracle Eva_ast.Build.(sub l u) |> Int_val.is_zero))
    && is_singleton ~oracle sub

let references =
  let rec aux acc = function
    | NoOffset _ -> acc
    | Field (_, sub) -> aux acc sub
    | Index (l, u, _, sub) ->
      let lrefs = Eva_ast.vars_in_exp l
      and urefs = Eva_ast.vars_in_exp u in
      let acc = Cil_datatype.Varinfo.Set.(union (union lrefs urefs) acc) in
      aux acc sub
  in
  aux Cil_datatype.Varinfo.Set.empty
