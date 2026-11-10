(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types
open Eval

include Sign_val

(* Bottom is a special value (`Bottom) in Eva, and need not be part of
   the lattice. Here, we have a value which is equivalent to it, defined
   there only for commodity. *)
let empty = { pos = false; zero = false; neg = false }

let pretty_typ _ = pretty

type context = unit
let context = Abstract_context.Leaf (module Unit_context)

(* Inclusion: test inclusion of each field. *)
let is_included v1 v2 =
  let bincl b1 b2 = (not b1) || b2 in
  bincl v1.pos v2.pos && bincl v1.zero v2.zero && bincl v1.neg v2.neg

(* Join of the lattice: pointwise logical or. *)
let join v1 v2 = {
  pos  = v1.pos  || v2.pos;
  zero = v1.zero || v2.zero;
  neg  = v1.neg  || v2.neg;
}

(* Meet of the lattice (called 'narrow' in Eva for historical reasons).
   We detect the case where the values have incompatible concretization,
   and report this as `Bottom. *)
let narrow v1 v2 =
  let r = {
    pos  = v1.pos  && v2.pos;
    zero = v1.zero && v2.zero;
    neg  = v1.neg  && v2.neg;
  } in
  if r = empty then `Bottom else `Value r

let top_int = top

let inject_int _ = inject_int

let constant _context _expr = function
  | Eva_ast.CInt64 (i, _, _) -> inject_int () i
  | _ -> top

(* Extracting function pointers from an abstraction. Not implemented
   precisely *)
let resolve_functions _ = `Top, true

let replace_base _substitution t = t

(** {2 Alarms} *)

let assume_non_zero v =
  if equal v zero
  then `False
  else if v.zero
  then `Unknown {v with zero = false}
  else `True

(* TODO: use the bound to reduce the value when possible. *)
let assume_bounded _ _ v = `Unknown v

let assume_not_nan ~assume_finite:_ _ v = `Unknown v
let assume_pointer v = `Unknown v
let assume_aligned _ v = `Unknown v
let assume_comparable _ v1 v2 = `Unknown (v1, v2)

(** {2 Forward transfer functions} *)

(* Functions [neg_unop], [plus], [mul] and [div] below are forward transformers
   for the mathematical operations -, +, *, /. The potential overflows and
   wrappings for the operations on machine integers are taken into account by
   the functions [truncate_integer] and [rewrap_integer]. *)

let bitwise_not typ v =
  match Ast_types.C.unroll_node typ with
  | TInt ikind | TEnum {ekind=ikind} ->
    if Cil.isSigned ikind
    then bitwise_not v
    else { pos = v.pos || v.zero; neg = false; zero = v.pos }
  | _ -> top

let forward_unop _context typ op v =
  match op with
  | Eva_ast.Neg -> `Value (neg_unop v)
  | BNot -> `Value (bitwise_not typ v)
  | LNot -> `Value (logical_not v)

let forward_binop _context _typ op v1 v2 =
  match op with
  | Eva_ast.PlusA  -> `Value (plus v1 v2)
  | MinusA -> `Value (plus v1 (neg_unop v2))
  | Mult   -> `Value (mul v1 v2)
  | Div    -> if equal zero v2 then `Bottom else `Value (cdiv v1 v2)
  | BAnd -> `Value (bitwise_and v1 v2)
  | BOr -> `Value (bitwise_or v1 v2)
  | BXor -> `Value (bitwise_xor v1 v2)
  | LAnd -> `Value (logical_and v1 v2)
  | LOr -> `Value (logical_or v1 v2)
  | _      -> `Value top

let rewrap_integer _context range v =
  if equal v zero then v
  else if range.Eval_typ.i_signed then top else pos_or_zero

(* Casts from type [src_typ] to type [dst_typ]. As downcasting can wrap,
   we only handle upcasts precisely *)
let forward_cast _context ~src_type ~dst_type v =
  let open Eval_typ in
  match src_type, dst_type with
  | TSInt range_src, TSInt range_dst ->
    if equal v zero then `Value v else
    if range_inclusion range_src range_dst then
      `Value v (* upcast *)
    else if range_dst.i_signed then
      `Value top (*dst_typ is signed, return all possible values*)
    else
      `Value pos_or_zero (* dst_typ is unsigned *)
  | _ ->
    (* at least one non-integer type. not handled precisely. *)
    `Value top


(** {2 Backward transfer functions} *)

(* Backward transfer functions are used to reduce the abstraction of a value,
   knowing other information. For example '[0+] > [0]' means that the
   first value can only be [+].

   In the OCaml signatures, 'None' means 'I cannot reduce'. *)

(* Value to return when no reduction is possible *)
let unreduced = `Value None
(* Function to use when a reduction is possible *)
let reduced v = `Value (Some v)

(* This function must reduce the value [right] assuming that the
   comparison [left op right] holds. *)
let backward_comp_right op ~left ~right =
  match op with
  | Req ->
    narrow left right >>- reduced
  | Rneq ->
    if equal left zero then
      narrow right non_zero >>- reduced
    else unreduced
  | Rle ->
    if ge_zero left then
      (* [left] is positive or zero. Hence, [right] is at least also positive
         or zero. *)
      if left.zero then
        (* [left] may be zero, [right] is positive or zero *)
        narrow right pos_or_zero >>- reduced
      else
        (* [left] is strictly positive, hence so is [right] *)
        narrow right pos >>- reduced
    else unreduced
  | Rlt ->
    if ge_zero left then
      narrow right pos >>- reduced
    else unreduced
  | Rge ->
    if le_zero left then
      if left.zero then
        narrow right neg_or_zero >>- reduced
      else
        narrow right neg >>- reduced
    else unreduced
  | Rgt ->
    if le_zero left then
      narrow right neg >>- reduced
    else unreduced

(* This functions must reduce the values [left] and [right], assuming
   that [left op right == result] holds. Currently, it is only implemented
   for comparison operators. *)
let backward_binop _ctx ~input_type:_ ~resulting_type:_ op ~left ~right ~result =
  match op with
  | Eva_ast.Ne | Eq | Le | Lt | Ge | Gt ->
    let op = Eva_ast.conv_relation op in
    if equal zero result then
      (* The comparison is false, as it always evaluate to false. Reduce by the
         fact that the inverse comparison is true.  *)
      let op = Logic_utils.opposite_relation op in
      let sym_op = Logic_utils.symmetric_relation op in
      backward_comp_right op ~left ~right >>- fun right' ->
      backward_comp_right sym_op ~left:right ~right:left >>- fun left' ->
      `Value (left', right')
    else if not result.zero then
      let sym_op = Logic_utils.symmetric_relation op in
      (* The comparison always hold, as it never evaluates to false. *)
      backward_comp_right op ~left ~right >>- fun right' ->
      backward_comp_right sym_op ~left:right ~right:left >>- fun left' ->
      `Value (left', right')
    else
      (* The comparison may or may not hold, it is not possible to reduce *)
      `Value (None, None)
  | _ -> `Value (None, None)

(* Not implemented precisely *)
let backward_unop _context ~typ_arg:_ _op ~arg:_ ~res:_ =
  `Value None

(* Not implemented precisely *)
let backward_cast _context ~src_typ:_ ~dst_typ:_ ~src_val:_ ~dst_val:_ =
  `Value None

(* Eva boilerplate, used to retrieve the domain. *)
let key = Structure.Key_Value.create_key "sign_values"
