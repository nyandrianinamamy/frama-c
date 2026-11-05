(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type signs = {
  pos: bool;  (** true: maybe positive, false: never positive *)
  zero: bool; (** true: maybe zero, false: never zero *)
  neg: bool;  (** true: maybe negative, false: never negative *)
}

let top =         { pos = true;  zero = true;  neg = true  }
let pos_or_zero = { pos = true;  zero = true;  neg = false }
let pos =         { pos = true;  zero = false; neg = false }
let neg_or_zero = { pos = false; zero = true;  neg = true  }
let neg =         { pos = false; zero = false; neg = true  }
let zero =        { pos = false; zero = true;  neg = false }
let non_zero =    { pos = true;  zero = false; neg = true  }

let ge_zero v = not v.neg
let le_zero v = not v.pos
let gt_zero v = not v.neg && not v.zero
let lt_zero v = not v.pos && not v.zero

include Datatype.Make(struct
    type t = signs
    include Datatype.Serializable_undefined
    let compare = Stdlib.compare
    let equal = Datatype.from_compare
    let hash = Hashtbl.hash
    let reprs = [top]
    let name = "Value.Sign_values.signs"
    let pretty fmt v =
      Format.fprintf fmt "%s%s%s"
        (if v.neg  then "-" else "")
        (if v.zero then "0" else "")
        (if v.pos  then "+" else "")
  end)

let inject_int i =
  if Z.lt i Z.zero then neg
  else if Z.gt i Z.zero then pos
  else zero

let neg_unop v = { v with neg = v.pos; pos = v.neg }

let bitwise_not v =
  { pos = v.neg; neg = v.pos || v.zero; zero = v.neg }

let logical_not v = { pos = v.zero; neg = false; zero = v.pos || v.neg }

let plus v1 v2 =
  let neg = v1.neg || v2.neg in
  let pos = v1.pos || v2.pos in
  let same_sign v1 v2 =
    (le_zero v1 && le_zero v2) || (ge_zero v1 && ge_zero v2)
  in
  let zero = not (same_sign v1 v2) || (v1.zero && v2.zero) in
  { neg; pos; zero }

let mul v1 v2 =
  let pos = (v1.pos && v2.pos) || (v1.neg && v2.neg) in
  let neg = (v1.pos && v2.neg) || (v1.neg && v2.pos) in
  let zero = v1.zero || v2.zero in
  { neg; pos; zero }

let cdiv v1 v2 =
  let pos = (v1.pos && v2.pos) || (v1.neg && v2.neg) || v2.zero in
  let neg = (v1.pos && v2.neg) || (v1.neg && v2.pos) || v2.zero in
  let zero = true in (* zero can appear with large enough v2 *)
  { neg; pos; zero }

let cmod v1 v2 =
  let pos = v1.pos || v2.zero in
  let neg = v1.neg || v2.zero in
  let zero = true in
  { neg; pos; zero }

(* The implementation of the bitwise operators below relies on this table
   giving the sign of the result according to the sign of both operands.

   For shift, we take the semantics of ACSL, Rocq, etc:
   x << -n (resp >>) = x >> n (resp <<)

       v1  v2   v1&v2   v1|v2   v1^v2   v1<<v2   v1>>v2
   ----------------------------------------------------
   |   +   +      +0      +       +0      +        +0
   |   +   0      0       +       +       +        +
   |   +   -      +0      -       -       +0       +
   |   0   +      0       +       +       0        0
   |   0   0      0       0       0       0        0
   |   0   -      0       -       -       0        0
   |   -   +      +0      -       -       -        -  /!\ -1 >>  1 == -1
   |   -   0      0       -       -       -        -
   |   -   -      -       -       +0      -        -  /!\ -1 << -1 == -1
*)

let bitwise_and v1 v2 =
  let pos = (v1.pos && (v2.pos || v2.neg)) || (v2.pos && v1.neg) in
  let neg = v1.neg && v2.neg in
  let zero = v1.zero || v1.pos || v2.zero || v2.pos in
  { neg; pos; zero }

let bitwise_or v1 v2 =
  let pos = (v1.pos && (v2.pos || v2.zero)) || (v1.zero && v2.pos) in
  let neg = v1.neg || v2.neg in
  let zero = v1.zero && v2.zero in
  { neg; pos; zero }

let bitwise_xor v1 v2 =
  let pos =
    (v1.pos && v2.pos) || (v1.pos && v2.zero) || (v1.zero && v2.pos)
    || (v1.neg && v2.neg)
  in
  let neg =
    (v1.neg && (v2.pos || v2.zero)) ||
    (v2.neg && (v1.pos || v1.zero))
  in
  let zero = (v1.zero && v2.zero) || (v1.pos && v2.pos) || (v1.neg && v2.neg) in
  { neg; pos; zero }

let bitwise_lsl a b =
  { a with zero = a.zero || (a.pos && b.neg) || (a.neg && b.neg) }

let bitwise_lsr a b =
  { a with zero = a.zero || (a.pos && b.pos) }

let logical_and v1 v2 =
  let pos = (v1.pos || v1.neg) && (v2.pos || v2.neg) in
  let neg = false in
  let zero = v1.zero || v2.zero in
  { pos; neg; zero }

let logical_or v1 v2 =
  let pos = v1.pos || v1.neg || v2.pos || v2.neg in
  let neg = false in
  let zero = v1.zero in
  { pos; neg; zero }
