(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval

type oracle = exp -> Cvalue.V.t
type getter = oracle:(exp -> Cvalue.V.t) -> lval -> Cvalue.V.t or_bottom

let convert_oracle (oracle : oracle) exp =
  match Ival.project_int_val (Cvalue.V.project_ival (oracle exp)) with
  | Some int_val -> int_val
  | None | exception Cvalue.V.Not_based_on_null -> Int_val.top

let default_oracle (get : getter) : oracle =
  (* Until Eva gives access to good oracles, we use this poor stupid oracle
     instead *)
  let rec oracle (exp : Eva_ast.exp) : Cvalue.V.t =
    match exp.node with
    | Lval lval ->
      (* Locations should never be empty so the safeguard on bottom
         should never trigger. *)
      get ~oracle lval |> Bottom.value ~bottom:Cvalue.V.bottom
    | Const CInt64 (i, _, _) ->
      Cvalue.V.inject_int i
    | Const CReal  (f, _, _) ->
      Fval.(F.of_float f |> singleton) |> Cvalue.V.inject_float
    | UnOp (op, e, typ) ->
      Cvalue_forward.forward_unop typ op (oracle e)
    | BinOp (op, e1, e2, { tnode = TFloat fkind }) ->
      Cvalue_forward.forward_binop_float (Fval.kind fkind) (oracle e1) op (oracle e2)
    | BinOp (op, e1, e2, typ) ->
      Cvalue_forward.forward_binop_int ~typ (oracle e1) op (oracle e2)
    | CastE (typ, e) ->
      let scalar_type t = Option.get (Eval_typ.classify_as_scalar t) in
      let src_type = scalar_type e.typ and dst_type = scalar_type typ in
      Cvalue_forward.forward_cast ~src_type ~dst_type (oracle e)
    | _ ->
      Self.fatal
        "This type of array index expression is not supported: %a"
        Eva_ast.pp_exp exp
  in (fun exp -> Eva_ast.const_fold exp |> oracle)
