(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types
open Lattice_bounds

(* If true, prints each operation performed for the tests. Otherwise, only
   prints wrong operations. *)
let print = false

let report bug format =
  if print || bug
  then Self.result ("%s" ^^ format) (if bug then "BUG " else "")
  else Format.ifprintf Format.std_formatter format


(* Tests the semantics of sign values, by comparison with the Ival semantics. *)
module Sign = struct

  module Sign = struct
    include Sign_value
    let zero = zero
    let pos = inject_int Cil_const.uintType Z.one
    let neg = inject_int Cil_const.uintType Z.minus_one
    let pos_or_zero = join zero pos
    let neg_or_zero = join zero neg
    let pos_neg = join pos neg
  end

  module Ival = struct
    include Ival
    let positive = inject_range (Some Z.one) None
    let negative = inject_range None (Some Z.minus_one)
    let pos irange =
      let max = Eval_typ.range_upper_bound irange in
      inject_range (Some Z.one) (Some max)
    let neg irange =
      let min = Eval_typ.range_lower_bound irange in
      inject_range (Some min) (Some Z.minus_one)
  end

  module Cval = Main_values.CVal

  (* List of pairs (ival, sign) such that γ(ival) ⊆ γ(sign) and all values in
     γ(sign) are in the range of [ikind]. *)
  let test_values ikind =
    let irange = Eval_typ.ik_range ikind in
    let list =
      [ Ival.zero, Sign.zero;
        Ival.pos irange, Sign.pos;
        Ival.zero, Sign.pos_or_zero;
        Ival.pos irange, Sign.pos_or_zero; ]
    in
    if not irange.Eval_typ.i_signed
    then list
    else
      list @
      [ Ival.neg irange, Sign.neg;
        Ival.zero, Sign.neg_or_zero;
        Ival.neg irange, Sign.neg_or_zero;
        Ival.pos irange, Sign.pos_neg;
        Ival.neg irange, Sign.pos_neg; ]

  let make_cvalue values =
    List.map (fun (ival, sign) -> Cvalue.V.inject_ival ival, sign) values

  (* Checks whether γ(ival) ⊆ γ(sign). *)
  let is_included cvalue sign =
    try
      let ival = Cvalue.V.project_ival cvalue in
      (not (Ival.contains_zero ival) || sign.Sign.zero) &&
      (Ival.(is_bottom (narrow ival positive)) || sign.Sign.pos) &&
      (Ival.(is_bottom (narrow ival negative)) || sign.Sign.neg)
    with Cvalue.V.Not_based_on_null -> Sign.(equal sign top)

  let test_unop unop typ values =
    let test (cval, sign) =
      let context = Abstract_value.{ from_domains = Unit_context.top } in
      let cval_res = Cval.forward_unop context typ unop cval in
      let sign_res = Sign.forward_unop context typ unop sign in
      let bug = not (Bottom.is_included is_included cval_res sign_res) in
      report bug "%a %a = %a  while  %a %a = %a"
        Eva_ast.pp_unop unop Cval.pretty cval (Bottom.pretty Cval.pretty) cval_res
        Eva_ast.pp_unop unop Sign.pretty sign (Bottom.pretty Sign.pretty) sign_res
    in
    List.iter test values

  let test_binop binop typ values =
    let test (cval1, sign1) (cval2, sign2) =
      let context = Abstract_value.{ from_domains = Unit_context.top } in
      let cval_res = Cval.forward_binop context typ binop cval1 cval2 in
      let sign_res = Sign.forward_binop context typ binop sign1 sign2 in
      let bug = not (Bottom.is_included is_included cval_res sign_res) in
      report bug "%a %a %a = %a  while  %a %a %a = %a"
        Cval.pretty cval1 Eva_ast.pp_binop binop Cval.pretty cval2
        (Bottom.pretty Cval.pretty) cval_res
        Sign.pretty sign1 Eva_ast.pp_binop binop Sign.pretty sign2
        (Bottom.pretty Sign.pretty) sign_res
    in
    List.iter (fun x -> List.iter (test x) values) values

  let test_typ ikind =
    let typ = Cil_const.mk_tint ikind
    and values = make_cvalue (test_values ikind) in
    let apply f op = f op typ values in
    List.iter (apply test_unop) [Neg; BNot; LNot];
    List.iter (apply test_binop)
      [PlusA; MinusA; Mult; Div; BAnd; BOr; BXor; LAnd; LOr]

  let test () = List.iter test_typ [IInt; IUInt]
end

(* Tests consequences of the laws of the reuse operation on the cvalue domain
   that need no concretization, on a few states and on every set of blocks
   among four variables:
   - [filter B S] binds exactly the blocks of [B] bound in [S], each to its
     offsetmap in [S]: it only forgets;
   - [filter] is idempotent: [filter B (filter B S) = filter B S];
   - [reuse W ~current_input:S ~previous_output:(filter (K ∪ W) S) = S];
   - on two maps C and O, [reuse W ~current_input:C ~previous_output:O]
     binds each block of [W] bound in O to its offsetmap in O, each other
     block bound in C to its offsetmap in C, and no other block: it takes
     the blocks of W from O and the others from C, even where O and C differ
     outside W. *)
module Cache_laws = struct

  module State = Cvalue_domain.State

  let bind vi v state =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size state

  let initialized = Cvalue.V_Or_Uninitialized.initialized
  let uninitialized = Cvalue.V_Or_Uninitialized.uninitialized

  let int n = initialized (Cvalue.V.inject_int (Z.of_int n))

  let address_of vi =
    initialized (Cvalue.V.inject (Base.of_varinfo vi) Ival.zero)

  (* The five states, over the variables [a], [b], [c] and [p]. *)
  let states (a, b, c, p) =
    let range = Ival.inject_range (Some Z.zero) (Some (Z.of_int 10)) in
    let range = initialized (Cvalue.V.inject_ival range) in
    let models =
      Cvalue.Model.[
        empty_map;
        empty_map |> bind a (int 1) |> bind b range |> bind c uninitialized
        |> bind p (address_of a);
        empty_map |> bind a (int 2) |> bind p (address_of b);
        top;
        bottom ]
    in
    List.map (fun s -> s, Locals_scoping.bottom ()) models

  (* All sets of blocks among the variables [vars]. *)
  let sets vars =
    let add_or_not sets vi =
      let b = Base.of_varinfo vi in
      sets @ List.map (Base.Hptset.add b) sets
    in
    List.fold_left add_or_not [ Base.Hptset.empty ] vars

  let bindings = function
    | Cvalue.Model.Map m ->
      Cvalue.Model.fold (fun b o acc -> (b, o) :: acc) m []
    | Top | Bottom -> []

  let same_binding (b, o) (b', o') =
    Base.equal b b' && Cvalue.V_Offsetmap.equal o o'

  let same_bindings l l' =
    List.length l = List.length l'
    && List.for_all (fun x -> List.exists (same_binding x) l') l

  (* [filter bases state] binds exactly the bases of [bases] bound in
     [state], to the same offsetmaps. On Top and Bottom, it is the identity.
     The filter of a map is a map: [bindings] gives no binding for Top and
     Bottom, which an empty map would not tell apart. *)
  let only_forgets bases (model, _) (filtered, _) =
    match model, filtered with
    | (Cvalue.Model.Top | Bottom), _ -> Cvalue.Model.equal model filtered
    | Map _, (Cvalue.Model.Top | Bottom) -> false
    | Map _, Map _ ->
      let kept (b, _) = Base.Hptset.mem b bases in
      same_bindings (List.filter kept (bindings model)) (bindings filtered)

  let test_filter state bases =
    let filtered = State.filter bases state in
    report (not (only_forgets bases state filtered))
      "filter %a %a = %a  forgets nothing or changes a binding"
      Base.Hptset.pretty bases State.pretty state State.pretty filtered;
    let again = State.filter bases filtered in
    report (not (State.equal again filtered))
      "filter %a (filter %a %a) = %a  is not filter %a %a = %a"
      Base.Hptset.pretty bases Base.Hptset.pretty bases State.pretty state
      State.pretty again Base.Hptset.pretty bases State.pretty state
      State.pretty filtered

  let test_reuse state key written =
    let output = State.filter (Base.Hptset.union key written) state in
    let result =
      State.reuse written ~current_input:state ~previous_output:output
    in
    report (not (State.equal result state))
      "reuse %a %a (filter (%a ∪ %a) %a) = %a"
      Base.Hptset.pretty written State.pretty state
      Base.Hptset.pretty key Base.Hptset.pretty written State.pretty state
      State.pretty result

  (* The bindings expected from [reuse written ~current_input:current
     ~previous_output:output] on two maps. *)
  let combined written current output =
    let from_output (b, _) = Base.Hptset.mem b written in
    let taken = List.filter from_output (bindings output) in
    let is_taken b = List.exists (fun (b', _) -> Base.equal b b') taken in
    let kept (b, _) = not (is_taken b) in
    taken @ List.filter kept (bindings current)

  (* Top and Bottom are left out: a supplied entry has no exit state that is
     Top or Bottom, and no call whose input is Top or Bottom reaches
     [reuse]. *)
  let test_reuse_frame current output written =
    match current, output with
    | (Cvalue.Model.Map _, _), (Cvalue.Model.Map _, _) ->
      let result =
        State.reuse written ~current_input:current ~previous_output:output
      in
      let expected = combined written (fst current) (fst output) in
      let ok =
        match fst result with
        | Map _ -> same_bindings expected (bindings (fst result))
        | Top | Bottom -> false
      in
      report (not ok)
        "reuse %a %a %a = %a  does not take W from the output and the rest \
         from the input"
        Base.Hptset.pretty written State.pretty current State.pretty output
        State.pretty result
    | _ -> ()

  (* The variables are created here, not when the module is initialized:
     each one takes a new identifier of variable, which would change the
     identifiers printed by other plug-ins in every run. *)
  let test () =
    let var name typ = Cil.makeGlobalVar name typ in
    let a = var "a" Cil_const.intType and b = var "b" Cil_const.intType
    and c = var "c" Cil_const.intType and p = var "p" Cil_const.voidPtrType in
    let states = states (a, b, c, p) and sets = sets [ a; b; c; p ] in
    let for_all l f = List.iter f l in
    for_all states (fun state ->
        for_all sets @@ fun bases ->
        test_filter state bases;
        for_all sets @@ fun written ->
        test_reuse state bases written);
    for_all states @@ fun current ->
    for_all states @@ fun output ->
    for_all sets @@ fun written ->
    test_reuse_frame current output written
end

(** Runs all tests. *)
let run () =
  Self.result "Runs unit tests: %s."
    (if print
     then "all operations will be printed"
     else  "only faulty operations will be printed");
  Sign.test ();
  Cache_laws.test ()
