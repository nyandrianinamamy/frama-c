(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Manipulate the type of numbers. *)

let add_cast ~loc ?name env kf ctx strnum t_opt e =
  let open Analyses_types in
  let e, env = match strnum with
    | Str_Z -> Gmp.Z.create ~loc ?name t_opt env kf e
    | Str_R -> Gmp.Q.create ~loc ?name t_opt env kf e
    | C_number -> e, env
  in
  match ctx with
  | None ->
    e, env
  | Some ctx ->
    let ty = Cil.typeOf e in
    match Gmp_types.Z.is_t ty, Gmp_types.Z.is_t ctx with
    | true, true ->
      (* Z --> Z *)
      e, env
    | false, true ->
      if Gmp_types.Q.is_t ty then
        (* R --> Z *)
        Gmp.Q.cast_to_z ~loc ?name env e
      else
        (* C integer --> Z *)
        let e =
          if not (Ast_types.C.is_integral ty) && strnum = C_number then
            (* special case for \null that must be casted to long: it is the
               only non integral value that can be seen as an integer, while the
               type system infers that it is C-representable (see
               tests/runtime/null.i) *)
            Cil.mkCast ~newt:Cil_const.longType e (* \null *)
          else
            e
        in
        Gmp.Z.create ~loc ?name t_opt env kf e
    | _, false ->
      if Gmp_types.Q.is_t ctx then
        if Gmp_types.Q.is_t ty then (* R --> R *)
          e, env
        else (* C integer or Z --> R *)
          Gmp.Q.create ~loc ?name t_opt env kf e
      else if Gmp_types.Z.is_t ty || strnum = Str_Z then
        (* Z --> C type or the integer is represented by a string:
           anyway, it fits into a C integer: convert it *)
        Gmp.Z.add_cast ~loc ?name env kf ctx e
      else if Gmp_types.Q.is_t ty || strnum = Str_R then
        (* R --> C type or the real is represented by a string *)
        Gmp.Q.add_cast ~loc ?name env kf ctx e
      else
        (* C type --> another C type *)
        Cil.mkCastT ~force:false ~oldt:ty ~newt:ctx e, env

let add_gmp_cast ~loc ?name env kf mdr_ty e =
  let ty = Cil.typeOf e in
  (* must be cast into a C type *)
  if not (Gmp_types.Z.is_t mdr_ty) && not (Gmp_types.Q.is_t mdr_ty) then
    if Gmp_types.Z.is_t ty then
      (* GMPz-type value casts into a C type *)
      Gmp.Z.add_cast ~loc ?name env kf mdr_ty e
    else if Gmp_types.Q.is_t ty then
      (* GMPq-type value casts into a C-type *)
      Gmp.Q.add_cast ~loc ?name env kf mdr_ty e
    else
      (* C-type value casts into an another C-type *)
      e, env
  else
    (* the mandatory type is a GMP *)
    e, env
