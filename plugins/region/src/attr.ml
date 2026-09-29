(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type attr = [ `Nullable | `Allocated | `Garbage | `Validread | `Written ]
type flags = A of int [@@ unboxed]
type mask = M of int [@@ unboxed]


let flag = function
  | `Nullable  -> 0b00001
  | `Allocated -> 0b00010
  | `Garbage   -> 0b00100
  | `Validread -> 0b01000
  | `Written   -> 0b10000
let all_flags =   0b11111

let generate_mask l =
  let rec mask (M m) = function
    | [] -> M m
    | attr :: rest -> mask (M (m lor flag attr)) rest
  in mask (M 0) l

let empty = A 0
let add a (A w) = A (flag a lor w)
let mem a (A w) = flag a land w <> 0
let union (A x) (A y) = A (x lor y)
let subset (A x) (A y) = (x lor y) = y

let iter f w =
  List.iter
    (fun a -> if mem a w then f a)
    [ `Nullable ; `Allocated ; `Garbage ; `Validread ]

let pp_attr fmt = function
  | `Nullable  -> Format.pp_print_string fmt "nullable"
  | `Allocated -> Format.pp_print_string fmt "allocated"
  | `Garbage   -> Format.pp_print_string fmt "garbage"
  | `Validread -> Format.pp_print_string fmt "validread"
  | `Written   -> Format.pp_print_string fmt "written"

let reversed = flag `Validread
(* flags that shall be merged with land instead of lor *)

let bottom = A reversed

let merge ?mask:(M m = M all_flags) (A x) (A y) =
  let x_m, y_m = x lor m, y lor m in
  let flip w = reversed lxor w in
  A ((x lor lnot m) lor (flip (flip x_m lor flip y_m)))

let pretty fmt w =
  begin
    Format.fprintf fmt "@[<hov 2>" ;
    let sep = ref false in
    let next a =
      if !sep then Format.fprintf fmt ",@," else sep := true ;
      pp_attr fmt a in
    iter next w ;
    Format.fprintf fmt "@]" ;
  end

let add_flag s f = merge s @@ add f bottom

open Cil_types

let is_local v =
  not (v.vglob || v.vformal)

let is_initialized ~garbage v =
  v.vglob || v.vdefined ||
  (v.vformal && not garbage) ||
  (v.vtemp && not @@ Ast_types.C.is_struct_or_union v.vtype)

let is_const v =
  (v.vformal || v.vglob || v.vdefined) &&
  Ast_types.C.is_const v.vtype

let cvar ~garbage v =
  let flags = ref empty in
  let set f = flags := add f !flags in
  if is_local v then set `Allocated ;
  if is_const v then set `Validread ;
  if not @@ is_initialized ~garbage v then set `Garbage ;
  !flags
