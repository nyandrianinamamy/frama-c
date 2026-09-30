(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Dictionary =
  State_builder.Hashtbl
    (Obfuscator_kind.Hashtbl)
    (Datatype.String.Hashtbl.Make(Datatype.String))
    (struct
      let name = "Obfuscator.Dictionary"
      let size = 97
      let dependencies = [ Ast.self ]
    end)

module Acsl_string_literals =
  State_builder.Hashtbl
    (Datatype.String.Hashtbl)
    (Cil_datatype.Logic_constant)
    (struct
      let name = "Obfuscator.Literal_strings"
      let size = 17
      let dependencies = [ Ast.self ]
    end)

let fresh kind name =
  let h = Dictionary.memo (fun _ -> Datatype.String.Hashtbl.create 17) kind in
  let idx = Datatype.String.Hashtbl.length h + 1 in
  let fresh = Obfuscator_kind.prefix kind ^ string_of_int idx in
  Datatype.String.Hashtbl.add h fresh name;
  fresh

let fresh_acsl_string_literal lc =
  let idx = Acsl_string_literals.length () + 1 in
  let fresh = "ACSL_STRING_" ^ string_of_int idx in
  Acsl_string_literals.add fresh lc;
  fresh

let pp_acsl_string_literal_dict fmt =
  let pp_entry s lc =
    Format.fprintf fmt "#define %s %a@\n" s Printer.pp_logic_constant lc
  in
  Acsl_string_literals.iter pp_entry

let has_acsl_string_literals () = not (Acsl_string_literals.length () = 0)

let iter_sorted_kind f k h =
  if Datatype.String.Hashtbl.length h > 0 then
    let f = f k in
    Datatype.String.Hashtbl.iter_sorted f h

let iter_sorted f =
  let cmp k1 k2 =
    Datatype.String.compare
      (Obfuscator_kind.prefix k1)
      (Obfuscator_kind.prefix k2)
  in
  Dictionary.iter_sorted ~cmp (iter_sorted_kind f)

let pretty_entry fmt k =
  Format.fprintf fmt "// %as@\n" Obfuscator_kind.pretty k;
  fun new_ old -> Format.fprintf fmt "#define %s %s@\n" new_ old

let pretty_kind fmt k =
  try
    let h = Dictionary.find k in
    iter_sorted_kind (pretty_entry fmt) k h
  with Not_found ->
    ()

let pretty fmt =
  Format.fprintf fmt "\
/* *********************************** */@\n\
/* start of dictionary for obfuscation */@\n\
/* *********************************** */@\n";
  iter_sorted (pretty_entry fmt);
  Format.fprintf fmt "\
/*********************************** */@\n\
/* end of dictionary for obfuscation */@\n\
/*********************************** */@\n@\n"

let mark_as_computed () =
  Dictionary.mark_as_computed (); Acsl_string_literals.mark_as_computed()

let is_computed () =
  Dictionary.is_computed () && Acsl_string_literals.is_computed ()
