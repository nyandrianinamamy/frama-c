(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

let dkey = Options.Dkey.rte

module Guard =
struct
  type downcast_kind = Signed | Unsigned | FloatToInt | Pointer

  type shift_kind = Left | Right

  type kind =
    | Division_by_zero
    | Out_of_bounds
    | Memory_access
    | Initialized
    | Pointer_alignment
    | Pointer_value
    | Shift of shift_kind
    | Downcast of downcast_kind

  type t = { kind: kind; pred: predicate }

  let make k p = {kind = k; pred = p}

  let kind t = t.kind
  let pred t = t.pred

  let priority t =
    match t.kind with
    | Pointer_value -> 0
    | Initialized -> 1
    | Pointer_alignment -> 2
    | Memory_access -> 3
    | Division_by_zero -> 4
    | Downcast _ -> 5
    | Out_of_bounds -> 6
    | Shift _ -> 7

  let pretty fmt g = Printer.pp_predicate fmt g.pred

  let compare g1 g2 =
    let cmp = compare (priority g1) (priority g2) in
    if cmp = 0
    then Cil_datatype.PredicateStructEq.compare g1.pred g2.pred else cmp
end

module Guards =
struct

  module Guards = Set.Make(Guard)
  module Terms = Terms.Id.Hashtbl

  let tbl = Terms.create 10

  let add t g =
    if not @@ Logic_utils.is_trivially_true (Guard.pred g) then
      match Terms.find_opt tbl t with
      | Some guards -> Terms.replace tbl t (Guards.add g guards)
      | None -> Terms.add tbl t (Guards.singleton g)

  let iter_on_guards t f =
    match Terms.find_opt tbl t with
    | Some guards -> Guards.iter (fun g -> f (Guard.pred g)) guards
    | _ -> ()

  let fold_guards ~default t f =
    match Terms.find_opt tbl t with
    | Some guards -> Guards.fold (fun g x -> f (Guard.pred g) x) guards default
    | _ -> default

  let remove t = Terms.remove tbl t

  let transfer t_src t_dst =
    begin match Terms.find_opt tbl t_src with
      | Some src_guards ->
        begin match Terms.find_opt tbl t_dst with
          | Some dst_guards ->
            Terms.replace tbl t_dst @@ Guards.union src_guards dst_guards
          | None -> Terms.add tbl t_dst src_guards
        end
      | None -> ()
    end;
    remove t_src

  let mem_guard_kind t kind =
    match Terms.find_opt tbl t with
    | Some guards -> Guards.exists (fun g' -> (Guard.kind g') = kind) guards
    | None -> false

  let clear () = Terms.clear tbl

  let pretty fmt () =
    let pp_data fmt d =
      Pretty_utils.pp_list
        ~pre:"[" ~suf:"]" ~sep:";@ " Guard.pretty fmt (Guards.elements d)
    in
    Terms.pretty
      ~item:(format_of_string "%a --> %a") Printer.pp_term pp_data fmt tbl
end

module Flags =
struct


  let needs_trivial () = Options.Rte.Lvl.get () = 3

  (** [needs_rte ()] returns [true] if [n > 0], where [n] is the level of
      correction from the option [-e-acsl-rte n]. If not set, the function
      returns [true] if [o < 3], where [o] is the level of optimization from
      the option [-e-acsl-O o]. *)
  let needs_rte () =
    if Options.Rte.Lvl.is_set ()
    then Options.Rte.Lvl.get () > 0
    else Options.O.get () < 3

  (** [needs_initialized okf] firstly depends on [-e-acsl-rte-initialized]. If
      it is not set,it depends on [-rte-initialized]. And finally, if neither of
      them are defined it returns [true] if [n > 1] where [n] is the level of
      correction from the option [-e-acsl-rte n]. *)
  let needs_initialized okf =
    if Options.Rte.Initialized.is_set ()
    then Options.Rte.Initialized.get ()
    else begin
      if RteGen.Options.DoInitialized.is_set ()
      then Option.fold ~none:false ~some:RteGen.Options.DoInitialized.mem okf
      else Options.Rte.Lvl.get () > 1
    end

  (** [needs_pointer_alignment ()] only depends on [-warn-unaligned-pointer]. *)
  let needs_pointer_alignment () = Kernel.UnalignedPointer.get ()

  (** [needs_pointer_alignment ()] only depends on [-warn-left-shift-negative]. *)
  let needs_left_shift_negative () = Kernel.LeftShiftNegative.get ()

  (** [needs_pointer_alignment ()] only depends on [-warn-pointer-downcast]. *)
  let needs_pointer_downcast () = Kernel.PointerDowncast.get ()

  (** [needs_rte_opts ~min_lvl modules] takes a list of boolean options and
      returns the value of the first one (in the list order) set by the user. If
      no modules are set then it compares the [min_lvl] value with [n] the
      current level of correction from the option [-e-acsl-rte n]. *)
  let needs_rte_opts ~min_lvl modules =
    let opt =
      List.fold_left
        (fun acc opt ->
           match acc with
           | Some _ -> acc
           | None ->
             let module Opt = (val opt : Parameter_sig.Bool) in
             if Opt.is_set ()
             then Some (Opt.get ())
             else None)
        None
        modules
    in
    Option.value_or_else opt ~none:(fun () -> Options.Rte.Lvl.get () > min_lvl)

  let needs_div_mod () =
    needs_rte_opts ~min_lvl:0
      [(module Options.Rte.DivMod); (module RteGen.Options.DoDivMod)]

  let needs_mem_access () =
    needs_rte_opts ~min_lvl:0
      [(module Options.Rte.Mem); (module RteGen.Options.DoMemAccess)]

  let needs_float_to_int () =
    needs_rte_opts ~min_lvl:0
      [(module Options.Rte.FloatToInt); (module RteGen.Options.DoFloatToInt)]

  let needs_implicit_downcast () =
    needs_rte_opts ~min_lvl:0 [(module Options.Rte.ImplicitDowncast)]

  let needs_pointer_value () =
    needs_rte_opts ~min_lvl:1 [(module Kernel.InvalidPointer)]

  let needs_right_shift_negative () =
    needs_rte_opts ~min_lvl:1 [(module Kernel.RightShiftNegative)]

  let needs_signed_downcast () =
    needs_rte_opts ~min_lvl:1 [(module Kernel.SignedDowncast)]

  let needs_unsigned_downcast () =
    needs_rte_opts ~min_lvl:1 [(module Kernel.UnsignedDowncast)]

  let pretty fmt () =
    let pp_initialized fmt () =
      if Options.Rte.Initialized.is_set ()
      then Format.fprintf fmt "all"
      else
        Kernel_function.Set.iter
          (Kernel_function.pretty fmt) (RteGen.Options.DoInitialized.get ())
    in
    Format.fprintf fmt "RTE flags state:\n \
                        \t division by zero: %b\n \
                        \t memory access: %b\n \
                        \t initialization set function: %a\n \
                        \t pointer alignment: %b\n \
                        \t pointer value: %b\n \
                        \t left shift negative: %b\n \
                        \t right shift negative: %b\n \
                        \t float to int: %b\n \
                        \t pointer downcast: %b\n \
                        \t signed downcast: %b\n \
                        \t unsigned downcast: %b\n \
                        \t implicit downcast: %b"
      (needs_div_mod ())
      (needs_mem_access ())
      pp_initialized ()
      (needs_pointer_alignment ())
      (needs_pointer_value ())
      (needs_left_shift_negative ())
      (needs_right_shift_negative ())
      (needs_float_to_int ())
      (needs_pointer_downcast ())
      (needs_signed_downcast ())
      (needs_unsigned_downcast ())
      (needs_implicit_downcast ())
end

(** The module [Undefined_behaviours] contains functions that makes a guard for
    each kind of undefined behavior listed below:
    - division by zero
    - memory access (read)
    - index out of bounds
    - initialization
    - pointer alignment
    - pointer value
    - left shift negative
    - right shift negative
    - signed downcast
    - unsigned downcast
    - pointer downcast *)
module Undefined_behaviours =
struct

  let preprocess_guard guard =
    Logic_normalizer.preprocess_predicate guard;
    Bound_variables.preprocess_predicate guard

  (** [div_by_zero ~loc divider] creates the predicate that checks if [divider]
      is not equal to [Z.zero]. The guard does not contain directly [divider]
      but a copy of it. *)
  let div_by_zero ~loc divider =
    let smart = not @@ Flags.needs_trivial () in
    let divider_cpy = Smart_term.copy ~smart divider in
    let pred =
      Smart_predicate.prel
        ~smart
        ~loc
        ~names:["division by zero"]
        Rneq
        divider_cpy
        (Logic_const.tint Z.zero)
    in
    preprocess_guard pred;
    Guard.make Division_by_zero pred

  (** [shift_negative ~loc ~kind shift] creates the predicate that checks if
      [shift] is greater or equal to [Z.zero]. *)
  let shift_negative ~loc ~kind shift =
    let smart = not @@ Flags.needs_trivial () in
    let names =
      match kind with
      | Guard.Left -> ["left shift negative"]
      | Right -> ["right shift negative"]
    in
    let shift_cpy = Smart_term.copy ~smart shift in
    let pred =
      Smart_predicate.prel
        ~smart
        ~loc
        ~names
        Rle (Logic_const.tint Z.zero) shift_cpy
    in
    preprocess_guard pred;
    Guard.make (Shift kind) pred

  (** [mem_access ~loc lv] creates the predicate that checks if [lv] is a
       valid read. *)
  let mem_access ~loc lv =
    let addr = Terms.mk_TAddrOrTStartOf ~loc lv in
    let pred =
      Logic_const.pvalid_read
        ~loc
        ~names:["memory access"]
        (Logic_const.here_label, addr)
    in
    preprocess_guard pred;
    Guard.make Memory_access pred

  (** [index_bound ~loc t size] creates the predicate that check if [t] is
      between [Z.zero] and the array's upper bound regards of its [size]. *)
  let index_bound ~loc t size =
    let smart = not @@ Flags.needs_trivial () in
    let t_cpy_1 = Smart_term.copy ~smart t in
    let t_cpy_2 = Smart_term.copy ~smart t in
    let pred =
      Smart_predicate.pand
        ~smart
        ~loc
        ~names:["index out of bounds"]
        (Smart_predicate.prel ~smart Rle (Logic_const.tint Z.zero) t_cpy_1)
        (Smart_predicate.prel ~smart Rlt t_cpy_2 (Logic_utils.expr_to_term size))
    in
    preprocess_guard pred;
    Guard.make Out_of_bounds pred

  (** [initialized ~loc ?label lv typ] creates the predicate that check if [lv]
      is initialized. *)
  let initialized ~loc ?(label = Logic_const.here_label) lv =
    let addr = Terms.mk_TAddrOrTStartOf ~loc lv in
    let pred =
      Logic_const.pinitialized ~loc ~names:["uninitialized"] (label, addr)
    in
    preprocess_guard pred;
    Guard.make Initialized pred

  (** [pointer_alignment ~loc t typ] creates the predicate that check if [t] is
      aligned regards of [typ]. *)
  let pointer_alignment ~loc t typ =
    let smart = not @@ Flags.needs_trivial () in
    let pred =
      Logic_const.paligned
        ~loc
        ~names:["pointer alignment"]
        (Smart_term.copy ~smart t, Smart_term.talignof ~smart ~loc typ)
    in
    preprocess_guard pred;
    Guard.make Pointer_alignment pred

  (** [pointer_value ~loc t] creates the predicate that check if [t] is [null]
      or an object pointer. *)
  let pointer_value ~loc t =
    let smart = not @@ Flags.needs_trivial () in
    let null = Logic_const.term ~loc Tnull t.term_type in
    let t_cpy_1 = Smart_term.copy ~smart t in
    let t_cpy_2 = Smart_term.copy ~smart t in
    let correct_ptr =
      if Ast_types.Acsl.is_fun_ptr (Ast_types.Acsl.unroll t.term_type)
      then Logic_const.pvalid_function ~loc t_cpy_1
      else
        Logic_const.pobject_pointer
          ~loc
          (Logic_const.here_label, t_cpy_1)
    in
    let pred =
      Smart_predicate.por
        ~smart
        ~loc
        ~names:["invalid pointer"]
        (Smart_predicate.prel ~smart ~loc Req null t_cpy_2)
        correct_ptr
    in
    preprocess_guard pred;
    Guard.make Pointer_value pred

  (** [downcast ~kind ~loc t (lb,ub)] creates the predicate that check if [t] is
      between [lb] and [ub]. *)
  let downcast ~kind ~loc t (lb,ub) =
    let smart = not @@ Flags.needs_trivial () in
    let on_bounds i =
      let t = Logic_const.tint i in
      match kind with
      | Guard.FloatToInt -> Logic_const.tlogic_coerce ~loc t Lreal
      | _ -> t
    in
    let on_t t =
      let t = Smart_term.copy ~smart t in
      match kind with
      | Pointer -> Logic_const.tcast ~loc t (Machine.uintptr_type ())
      | _ -> t
    in
    let names = match kind with
      | Signed -> ["signed downcast"]
      | Unsigned -> ["unsigned downcast"]
      | FloatToInt -> ["float to int"]
      | Pointer -> ["pointer downcast"]
    in
    let pred =
      Smart_predicate.pand
        ~smart
        ~loc
        ~names
        (Smart_predicate.prel ~smart ~loc Rle (on_bounds lb) (on_t t))
        (Smart_predicate.prel ~smart ~loc Rle (on_t t) (on_bounds ub))
    in
    preprocess_guard pred;
    Guard.make (Guard.Downcast kind) pred
end

let rte_visitor =
  object(self)

    inherit E_acsl_visitor.visitor dkey

    method private trivially_aligned t typ ptyp: bool =
      if Ast_types.C.is_void ptyp || Ast_types.C.is_fun ptyp
      then
        (* - From an alignment point of view, casting to void* is always OK
            (except for function pointers, but anyway, the problem is not
            alignment)
           - Alignment does not make sense for functions *)
        true
      else
        let typ_align = Cil.bytesAlignOf ptyp in
        if Ast_types.C.is_void_ptr typ || Ast_types.C.is_fun_ptr typ
        then false
        else
        if Ast_types.C.is_integral typ
        then match Logic_utils.constFoldTermToInt t with
          | Some value when Z.(zero = (value mod of_int typ_align)) -> true
          | _ -> false
        else
          match t.term_node with
          | TAddrOf (TVar vi, TNoOffset) | TStartOf (TVar vi, TNoOffset) ->
            Option.fold ~none:false
              ~some:(fun v ->
                  0 = Cil.bytesAlignOfVarinfo v mod typ_align)
              (vi.lv_origin)
          | _ -> false

    (** [skip_pointer_alignment t] @return [true] if [t] already has a
        [Pointer_alignment] kind guard in the table. *)
    method private skip_pointer_alignment t =
      Guards.mem_guard_kind t Pointer_alignment

    (** [add_div_mod ~orig divider] adds an entry for [orig] if [divider] can
        be equal to zero. *)
    method private add_div_mod ~orig divider =
      if Flags.needs_div_mod () then
        Guards.add orig
          (Undefined_behaviours.div_by_zero ~loc:orig.term_loc divider)

    (** [add_shift_negative ~orig ~kind shift] adds an entry for [orig] if
        [shift] can be negative. *)
    method private add_shift_negative ~orig ~kind shift =
      if Misc.is_signed_int shift.term_type &&
         (kind = Guard.Left && Flags.needs_left_shift_negative ()) ||
         (kind = Guard.Right && Flags.needs_right_shift_negative ())
      then
        Guards.add orig
          (Undefined_behaviours.shift_negative ~loc:orig.term_loc ~kind shift)

    (** [add_index ~index size] adds [index] as key in [table] with a
        guard that checks if [index] is between [0] (included) and [size]
        (excluded). *)
    method private add_index ~index size =
      Guards.add index
        (Undefined_behaviours.index_bound ~loc:index.term_loc index size)

    (** [add_mem_access ~orig lv] checks if the lvalue [lv] is a
        variable or a dereference (other cases are not checked). In both, it
        calls the function [unroll_offset] with the information of being a
        dereference or not through the [~is_deref] argument. *)
    method private add_mem_access ~orig lv =
      let rec unroll_offset ~is_deref off typ =
        match off with
        | TNoOffset when is_deref ->
          Guards.add orig
            (Undefined_behaviours.mem_access ~loc:orig.term_loc lv)
        | TIndex (index, off) ->
          begin match Ast_types.C.unroll_node typ with
            | TArray (typ, Some size) ->
              let index = Logic_normalizer.get_term index in
              self#add_index ~index size;
              unroll_offset ~is_deref off typ
            (* if no size provided, then we act as it is a dereferencement. *)
            | TArray (typ, None) -> unroll_offset ~is_deref:true off typ
            | _ ->
              Options.abort "%a is type %a but should be type array"
                Printer.pp_term_lval lv
                Printer.pp_typ typ
          end
        | TField (fi, off) -> unroll_offset ~is_deref off fi.ftype
        | _ -> ()
      in
      if Flags.needs_mem_access () then
        match lv with
        | TVar v, off ->
          begin match v.lv_type with
            | Ctype typ -> unroll_offset ~is_deref:false off typ
            | _ -> ()
          end
        | TMem lh, off ->
          if not @@ Ast_types.Acsl.is_plain_fun @@ Cil.typeOfTermLval lv
          then begin
            let lh = Logic_normalizer.get_term lh in
            try
              unroll_offset ~is_deref:true off @@
              Ast_types.C.direct_pointed @@
              Ast_types.Acsl.get_ctype lh.term_type
            with  | _ ->
              Options.abort "%a is dereferenced but it is a not pointer type %a"
                Printer.pp_term_lval lv
                Printer.pp_logic_type lh.term_type
          end
        | _ -> ()

    (** [add_array_comparison tl tr] applies the analysis on the range of the
        array [tl[0..size(tl)]] (respectively [tr[0..size(tr)]]) instead of
        [tl] (respectively [tr]) *)
    method private add_array_comparison tl tr =
      let both x y f = f x; f y in
      both tl tr @@ fun t ->
      let rt =
        Logic_const.term
          ~loc:t.term_loc
          (TLval (Smart_term.trange_array ~loc:t.term_loc t))
          (Ast_types.Acsl.direct_array_element t.term_type)
      in
      ignore @@ self#vterm rt;
      Guards.transfer rt t

    (** [add_initialized ~orig ~loc lv typ] adds an entry for [orig] if [lv]
        is a C variable. *)
    method private add_initialized ~orig ~loc lv typ =
      let needs_guard lv =
        match lv with
        | TVar { lv_kind = (LVQuant | LVLocal | LVFormal) }, _ -> false
        | TVar { lv_origin = Some vi }, TNoOffset ->
          not (vi.vglob || vi.vformal || vi.vtemp) &&
          not (Ast_types.C.is_struct_or_union typ)
        (* Frama-C kernel ensures that '__retres' is always initialized. *)
        | TResult _, TNoOffset -> false
        | _ -> not Ast_types.C.(is_fun typ || is_struct_or_union typ)
      in
      if Flags.needs_initialized self#current_kf && needs_guard lv then
        Guards.add orig (Undefined_behaviours.initialized ~loc lv)

    (** [add_aligned ~orig t typ] adds an entry for [orig] if [t] has a pointer
        type. *)
    method private add_aligned ~orig t typ =
      if Flags.needs_pointer_alignment () &&
         not (self#skip_pointer_alignment orig) then begin
        (* The type has to be a pointer type, otherwise the function
           [Ast_types.direct_pointed_type] can fail. *)
        assert (Ast_types.C.is_ptr typ);
        let pointed_typ = Ast_types.C.direct_pointed typ in
        if Cil.isCompleteType pointed_typ
        then
          begin
            let t = Logic_normalizer.get_term @@ Cil.stripTermCasts t in
            if Flags.needs_trivial () ||
               not (self#trivially_aligned t typ pointed_typ)
            then
              Guards.add orig
                (Undefined_behaviours.pointer_alignment
                   ~loc:orig.term_loc t pointed_typ)
          end
        else
          Options.warning ~current:true ~once:true
            "cannot create the pointer alignment guard of %a because %a is \
             an incomplete type"
            Printer.pp_term orig
            Printer.pp_typ pointed_typ
      end

    (** [add_aligned_cast ~orig t dst] adds an entry for [orig] if [dst] the
        destination type of the cast is a pointer type. *)
    method private add_aligned_cast ~orig t dst =
      let aux src =
        match Ast_types.C.unroll_node src,  Ast_types.C.unroll_node dst with
        (* From int, To pointer *)
        | TInt _, TPtr _ -> self#add_aligned ~orig orig dst
        (* From pointer, To pointer *)
        | TPtr _, TPtr _ -> self#add_aligned ~orig t dst
        | _ -> ()
      in
      match Ast_types.Acsl.unroll t.term_type with
      | Ctype src -> aux src
      | _ -> ()

    (** [add_aligned_access lv] adds an entry for [t] if [lv = *t]. *)
    method private add_aligned_access lv =
      match lv with
      (* this case will be handle later *)
      | TMem ({term_node = TLval _}), _ -> ()
      | TMem ({term_type = Ctype typ} as t), _ ->
        let t = Logic_normalizer.get_term t in
        self#add_aligned ~orig:t t typ
      | _ -> ()

    (** [add_pointer_value] associates [orig] to a guard that check if [orig] is
        a pointer value in the table. *)
    method private add_pointer_value ~orig =
      if Flags.needs_pointer_value () then
        let pointed_typ =
          Ast_types.Acsl.(direct_pointed_ctype @@ unroll orig.term_type)
        in
        if Cil.isCompleteType pointed_typ
        then
          Guards.add orig
            (Undefined_behaviours.pointer_value ~loc:orig.term_loc orig)
        else
          Options.warning ~current:true ~once:true
            "cannot create the invalid pointer guard of %a because %a is \
             an incomplete type"
            Printer.pp_term orig
            Printer.pp_typ pointed_typ

    (** [add_pointer_value_cast ~orig dst] adds an entry for [orig] if [dst]
        the destination type of the cast is a pointer type. *)
    method private add_pointer_value_cast ~orig dst =
      let aux src =
        match Ast_types.C.unroll_node src,  Ast_types.C.unroll_node dst with
        (* From int, To pointer *)
        | TInt _, TPtr _ -> self#add_pointer_value ~orig
        | _ -> ()
      in
      match Ast_types.Acsl.unroll orig.term_type with
      | Ctype src -> aux src
      | _ -> ()

    (** [add_C_downcast ~orig t src dst] adds an entry for [orig] if the
        [dst] type is 'smaller' than the source type and the corresponding
        options are set on. *)
    method private add_C_downcast ~orig ~implicit t src dst =
      let get_bounds size is_signed =
        if is_signed then Cil.min_signed_number size, Cil.max_signed_number size
        else Z.zero, Cil.max_unsigned_number size
      in
      match Ast_types.C.unroll_node src, Ast_types.C.unroll_node dst with
      (* From int, To int *)
      | TInt src_ik, TInt dst_ik ->
        let dst_signed = Cil.isSigned dst_ik in
        let kind =
          if dst_signed then Guard.Signed else Unsigned
        in
        if dst_signed && Flags.needs_signed_downcast () ||
           not dst_signed && Flags.needs_unsigned_downcast () ||
           implicit && Flags.needs_implicit_downcast ()
        then
          let src_signed = Cil.isSigned src_ik in
          let   src_size = Cil.bitsSizeOfInt src_ik in
          let   dst_size = Cil.bitsSizeOfInt dst_ik in
          if dst_size < src_size ||
             src_size == dst_size && dst_signed <> src_signed
          then
            Guards.add orig
              (Undefined_behaviours.downcast ~kind ~loc:orig.term_loc t
                 (get_bounds dst_size dst_signed))
      (* From float, To int *)
      | TFloat _, TInt ikind ->
        if Flags.needs_float_to_int () ||
           implicit && Flags.needs_implicit_downcast ()
        then
          let signed = Cil.isSigned ikind in
          let   size = Cil.bitsSizeOfInt ikind in
          Guards.add orig
            (Undefined_behaviours.downcast
               ~kind:Guard.FloatToInt
               ~loc:orig.term_loc
               t
               (get_bounds size signed))
      (* From pointer, To int *)
      | TPtr _, TInt ikind ->
        if Flags.needs_pointer_downcast () &&
           not Ast_types.C.(is_intptr_t dst || is_uintptr_t dst) ||
           implicit && Flags.needs_implicit_downcast ()
        then
          let signed = Cil.isSigned ikind in
          let   size = Cil.bitsSizeOfInt ikind in
          Guards.add orig
            (Undefined_behaviours.downcast
               ~kind:Guard.Pointer
               ~loc:orig.term_loc
               t
               (get_bounds size signed))
      | _ -> ()

    (** [add_logic_downcast ~orig t src dst] adds an entry for [orig]. *)
    method private add_logic_downcast ~orig ~implicit t src dst =
      let get_bounds size is_signed =
        if is_signed then Cil.min_signed_number size, Cil.max_signed_number size
        else Z.zero, Cil.max_unsigned_number size
      in
      match src, Ast_types.C.unroll_node dst with
      (* From integer, To int *)
      | Linteger, TInt dst_ik ->
        let dst_signed = Cil.isSigned dst_ik in
        let kind =
          if dst_signed then Guard.Signed else Unsigned
        in
        if dst_signed && Flags.needs_signed_downcast () ||
           not dst_signed && Flags.needs_unsigned_downcast () ||
           implicit && Flags.needs_implicit_downcast ()
        then
          let dst_size = Cil.bitsSizeOfInt dst_ik in
          Guards.add orig
            (Undefined_behaviours.downcast ~kind ~loc:orig.term_loc t
               (get_bounds dst_size dst_signed))
      (* From real, To int *)
      | Lreal, TInt ikind ->
        if Flags.needs_float_to_int () ||
           implicit && Flags.needs_implicit_downcast ()
        then
          let signed = Cil.isSigned ikind in
          let   size = Cil.bitsSizeOfInt ikind in
          Guards.add orig
            (Undefined_behaviours.downcast
               ~kind:Guard.FloatToInt
               ~loc:orig.term_loc
               t
               (get_bounds size signed))
      | _ -> ()

    (** [add_downcast ~orig t dst] distinguishes logic downcast, i.e from a
        logic type to a C type, and C downcast, i.e between two C types. *)
    method private add_downcast ~orig ?(implicit = false) t dst =
      match Ast_types.Acsl.unroll t.term_type with
      | Ctype src -> self#add_C_downcast ~orig ~implicit t src dst
      | _ -> self#add_logic_downcast ~orig ~implicit t t.term_type dst

    method !vterm t =
      let t = Logic_normalizer.get_term t in
      begin match t.term_node with
        | TBinOp ((Div | Mod),_,divider) ->
          let divider = Logic_normalizer.get_term divider in
          self#add_div_mod ~orig:t divider
        | TBinOp ((PlusPI | MinusPI), _, t2) ->
          let t2 = Logic_normalizer.get_term t2 in
          self#add_pointer_value ~orig:t;
          (* [t2] has to be at most a [ILongLong] (typing constraint) *)
          self#add_downcast ~orig:t2 ~implicit:true t2 (Cil_const.mk_tint ILongLong)
        | TBinOp (Shiftlt,t1,t2) ->
          let t1 = Logic_normalizer.get_term t1 in
          let t2 = Logic_normalizer.get_term t2 in
          self#add_shift_negative ~orig:t ~kind:Left t1;
          (* [t2] has to be at most a [IULong] (typing constraint) *)
          self#add_downcast ~orig:t2 ~implicit:true t2 (Cil_const.mk_tint IULong)
        | TBinOp (Shiftrt,t1,t2) ->
          let t1 = Logic_normalizer.get_term t1 in
          let t2 = Logic_normalizer.get_term t2 in
          self#add_shift_negative ~orig:t ~kind:Right t1;
          (* [t2] has to be at most a [IULong] (typing constraint) *)
          self#add_downcast ~orig:t2 ~implicit:true t2 (Cil_const.mk_tint IULong)
        | TLval lv ->
          begin match Ast_types.Acsl.unroll t.term_type with
            | Ctype typ ->
              self#add_mem_access ~orig:t lv;
              self#add_initialized ~orig:t ~loc:t.term_loc lv typ;
              self#add_aligned_access lv;
              if Ast_types.C.is_ptr typ then begin
                self#add_pointer_value ~orig:t;
                self#add_aligned ~orig:t t typ
              end
            | _ -> ()
          end
        (* [false] means an explicit cast into a C type *)
        | TCast (false,ty,t') ->
          let t' = Logic_normalizer.get_term t' in
          begin match Ast_types.Acsl.unroll ~unroll_typedef:false ty with
            | Ctype dst ->
              self#add_pointer_value_cast ~orig:t dst;
              self#add_aligned_cast ~orig:t t' dst;
              self#add_downcast ~orig:t t' dst
            | _ ->
              Options.fatal
                "Explicit conversion to a C type, but %a is not a C type"
                Printer.pp_logic_type ty
          end
        | TStartOf _ | TAddrOf _ -> self#add_pointer_value ~orig:t
        | _ -> ()
      end;
      Cil.DoChildren

    method !vpredicate p =
      let p = Logic_normalizer.get_pred p in
      match p.pred_content with
      | Paligned (_,v) ->
        let v = Logic_normalizer.get_term v in
        self#add_div_mod ~orig:v v;
        (* [v] has to be at most a [size_t] (typing constraint) *)
        self#add_downcast ~orig:v ~implicit:true v (Machine.sizeof_type ());
        Cil.DoChildren
      | Prel((Req | Rneq),t1,t2) when Logic_utils.is_C_array t1 &&
                                      Logic_utils.is_C_array t2 ->
        let t1 = Logic_normalizer.get_term t1 in
        let t2 = Logic_normalizer.get_term t2 in
        self#add_array_comparison t1 t2;
        Cil.SkipChildren
      | Pseparated tlist ->
        let deref t = ((TMem t),TNoOffset) in
        List.iter
          (fun t ->
             let t = Logic_normalizer.get_term t in
             self#add_mem_access ~orig:t (deref t))
          tlist;
        Cil.DoChildren
      | _ -> (); Cil.DoChildren
  end

let preprocess ast =
  if Flags.needs_rte ()
  then begin
    Options.debug ~level:2 ~dkey "%a" Flags.pretty ();
    ignore @@ rte_visitor#visit_file ast;
    Options.feedback ~dkey "RTE analysis done on the AST.%!";
    Options.debug ~level:3 ~dkey "Result of the RTE analysis.%!";
    Options.debug ~level:3 ~dkey "%a%!" Guards.pretty ()
  end else
    Options.feedback ~level:3 ~dkey "Skip the RTE analysis.%!"

let preprocess_predicate ~kf p =
  if Flags.needs_rte ()
  then begin
    Options.debug ~level:2 ~dkey "%a" Flags.pretty ();
    rte_visitor#set_current_kf kf;
    ignore @@ rte_visitor#visit_predicate p;
    Options.feedback ~dkey "RTE analysis done on %a.%!"
      Printer.pp_predicate p;
    Options.debug ~level:3 ~dkey "Result of the RTE analysis.%!";
    Options.debug ~level:3 ~dkey "%a%!" Guards.pretty ()
  end else
    Options.feedback ~dkey "Skip the RTE analysis on %a.%!"
      Printer.pp_predicate p

let needs_rte_guards = Flags.needs_rte

let iter_on_guards = Guards.iter_on_guards

let fold_guards ~default = Guards.fold_guards ~default

let remove t = Guards.remove t

let transfer_guards = Guards.transfer

let clear () = Guards.clear ()
