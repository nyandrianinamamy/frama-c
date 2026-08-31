(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Eval
open Cell_oracle
open Lattice_bounds
module Location = Cell_location


(* --- Arguments of the internal functors --- *)

type 'value builtin = 'value list -> 'value or_bottom

(* Values used for the collaborative evaluation. *)
module type GenericValue =
sig
  type t
  val top : t
  val to_cvalue : t -> Cvalue.V.t
  val builtins: (string * t builtin) list
  val dependencies : t Abstract_value.dependencies
  val backward_is_finite : bool -> Cil_types.fkind -> t -> t or_bottom
end

(* Values used in the memory model. *)
module type CellValue =
sig
  include Typed_memory.Value
  type value (* the value without uninitialized state *)
  val top : t
  val bottom : t (* used for set of values containing only escaping addresses *)
  val narrow : t -> t -> t or_bottom
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
  val is_topint : t -> bool
  val is_bottom : t -> bool
  val is_initialized : t -> bool
  val to_cvalue : t -> Cvalue.V.t
  val to_value : t -> value or_bottom
  val of_value : value -> t
  val of_flagged : value Eval.flagged_value -> t
  val map' : (value -> value or_bottom) -> t -> t or_bottom
end


(* --- The memory model of a base --- *)

module BaseModel
    (Config : Typed_memory.Config)
    (CellValue : CellValue) =
struct
  module Memory = Typed_memory.Make (Config) (CellValue)

  module Prototype =
  (* Datatype *)
  struct
    include Datatype.Undefined
    include Memory
    let name = "Cell_memory.BaseModel(" ^ CellValue.datatype_name ^ ")"
    let reprs = [ Memory.top ]
  end

  include Datatype.Make (Prototype)

  let incr_bound = Memory.incr_bound
  let pretty = Memory.pretty
  let top = Memory.top
  let is_top = Memory.is_top
  let is_included = Memory.is_included
  let narrow = fun m1 _m2 -> m1
  let join = Memory.join
  let smash ~oracle = Memory.join ~oracle:(fun _ -> oracle)
  let widen hint = Memory.widen (fun ~size -> CellValue.widen ~size ~hint)

  let get ~oracle m loc =
    match loc with
    | `Top -> CellValue.top
    | `Value loc -> Memory.get ~oracle m loc

  let extract ~oracle m loc =
    match loc with
    | `Top -> Memory.top
    | `Value loc -> Memory.extract ~oracle m loc

  let erase ~oracle ~weak m loc bit_value =
    match loc with
    | `Top -> Memory.top
    | `Value loc -> Memory.erase ~oracle ~weak m loc bit_value

  let set ~oracle ~weak new_v m loc =
    match loc with
    | `Top -> Memory.top
    | `Value loc -> Memory.set ~oracle ~weak m loc new_v

  let reinforce ~oracle f m loc =
    match loc with
    | `Top -> `Value m
    | `Value loc -> Memory.reinforce ~oracle f m loc

  let replace ~oracle ~weak dst loc src =
    match loc with
    | `Top -> Memory.top
    | `Value loc -> Memory.overwrite ~oracle ~weak dst loc src

  let map = Memory.map
  let iter = Memory.iter
  let for_all = Memory.for_all
  let fold = Memory.fold

  let segmentation_hint ~oracle m loc bounds =
    match loc with
    | `Top -> Memory.top
    | `Value loc -> Memory.segmentation_hint ~oracle m loc bounds
end


(* --- Generic functor for building abstract domains --- *)

module Make_Generic_Memory (Value : CellValue) =
struct
  (* Configuration of the memory model *)
  module Config = struct
    let deps = [Ast.self]
    let slice_limit = Parameters.MultidimSegmentLimit.get
    let disjunctive_invariants =
      Parameters.MultidimDisjunctiveInvariants.get
  end

  module BaseModel = BaseModel (Config) (Value)

  (* References to variables inside array segmentation.
      For instance if an array A is described with the segmentation
      0..i-1 ; i ; i+1..10
      then, everytime i is changed, the segmentation must be updated. This requires
      referencing every base where at least one segmentation references i. *)
  module Referers = Base.Hptset (* The set of bases referencing the variable *)

  (* The domain can be set to track a subset of bases *)
  module Tracking = Base.Hptset

  (* The domain is essentially a map from bases to individual memory abstractions *)
  module Map_value = struct
    include Datatype.Pair (BaseModel) (Referers)
    let top = BaseModel.top, Referers.empty
    let is_top (m,r) = BaseModel.is_top m && Referers.is_empty r
  end

  module Map_Info = struct
    let initial_values = []
    let dependencies = [ Ast.self ]
  end

  module MemoryMap = struct
    include Hptmap.Make (Base.Base) (Map_value) (Map_Info)

    let pretty_debug = pretty

    let pretty fmt (state : t)  =
      let pp_val fmt (m,_r) = BaseModel.pretty fmt m in
      Pretty.pretty_seq2 ~format:"@[<v>%t@]" ~sep:"@ " ~item:"%a -> %a"
        Base.pretty pp_val fmt (to_seq state)

    let find_or_top (state : t) (b : Base.t) =
      try find b state with Not_found -> Map_value.top

    (* Update or remove if top *)
    let add (b : Base.t) (v : Map_value.t) (state : t) =
      if Map_value.is_top v
      then remove b state
      else add b v state
  end

  include Datatype.Pair_with_collections
      (MemoryMap)
      (Datatype.Option (Tracking))

  type base = Base.t
  type base_model = BaseModel.t
  type offset = Location.offset
  type location = Location.t
  type value = Value.t

  let datatype_name =
    "Cell_memory.Make_Generic_Memory(" ^ Value.datatype_name ^ ")"

  let cache_name s =
    Hptmap_sig.PersistentCache (datatype_name ^ "." ^ s)

  (* Pretty printing *)

  let _pretty_debug =
    Pretty_utils.pp_pair
      MemoryMap.pretty_debug
      (Pretty_utils.pp_opt Tracking.pretty)

  let pretty fmt (state : t) =
    let base_map, _ = state in
    MemoryMap.pretty fmt base_map

  (* Base tracking : defines what bases must be followed *)

  let covers_base (tracked : Tracking.t option) (b : base) : bool =
    match b with
    | Base.Var (vi, _) ->
      not (Ast_types.C.is_volatile vi.vtype) &&
      Option.fold ~none:true ~some:(Tracking.mem b) tracked
    | Null -> true
    | CLogic_Var _ | Allocated (_, _, _) -> false

  let set_tracking (base_map, tracked : t) bases =
    let set = Option.value ~default:Tracking.empty tracked in
    let tracked = List.fold_right Tracking.add bases set in
    (* Only keep tracked bases in the current base map *)
    let base_map = MemoryMap.inter_with_shape tracked base_map in
    base_map, Some tracked

  (* References *)

  let add_references (state : t) (referee : base) (referers' : base list) : t =
    let base_map, tracked = state in
    let memory, referers = MemoryMap.find_or_top base_map referee in
    let referers'' = Referers.union referers (Referers.of_list referers') in
    MemoryMap.add referee (memory, referers'') base_map, tracked

  let add_references_l state (referees : base list) (referers : base list) =
    List.fold_left
      (fun state b -> add_references state b referers)
      state referees

  let update_var_references ~oracle (dst : Cil_types.varinfo)
      (src : Eva_ast.exp option) (base_map,tracked : t) =
    let incr =
      let open Option.Operators in
      let* expr = src in
      let is_dst (exp : Eva_ast.exp) = match exp.node with
        | Lval { node = Var v, NoOffset } -> Cil_datatype.Varinfo.equal dst v
        | _ -> false
      in
      match expr.node with
      | BinOp ((PlusA|PlusPI), e1, e2, _typ) when is_dst e1 ->
        Eva_ast.fold_to_integer e2
      | BinOp ((PlusA|PlusPI), e1, e2, _typ) when is_dst e2 ->
        Eva_ast.fold_to_integer e1
      | BinOp ((MinusA|MinusPI), e1, e2, _typ) when is_dst e1 ->
        Option.map Z.neg (Eva_ast.fold_to_integer e2)
      | _ -> None
    in
    (* [oracle] must be the oracle before the (non-invertible)
        assignment of the referee to allow removing of eventual empty slice
        before the bound leaves the segmentation. *)
    let referers = snd (MemoryMap.find_or_top base_map (Base.of_varinfo dst)) in
    let update_ref base base_map =
      let update (memory, refs) =
        let oracle = convert_oracle oracle in
        BaseModel.incr_bound ~oracle dst incr memory, refs
      in
      MemoryMap.replace (Option.map update) base base_map
    in
    let base_map = Referers.fold update_ref referers base_map in
    (* If increment is None, every reference to dst should have been removed by
        Memory.incr_bound *)
    let base_map =
      if Option.is_none incr then
        MemoryMap.replace
          (Option.map (fun (memory, _refs) -> memory, Referers.empty))
          (Base.of_varinfo dst)
          base_map
      else
        base_map
    in
    base_map, tracked

  let remove_base_references ~oracle base state =
    match Base.to_varinfo base with
    | exception Base.Not_a_C_variable -> state (* only references to variables are kept *)
    | vi -> update_var_references ~oracle vi None state

  let update_references ~oracle (dst : location)
      (src : Eva_ast.exp option) (state : t) =
    match Location.to_singleton_var dst with
    | Some vi ->
      update_var_references ~oracle vi src state
    | None -> (* Weak update of referee, remove references *)
      Location.fold
        (fun b _offset state -> remove_base_references ~oracle b state) dst state

  (* Accesses *)

  let read :
    type a .
    (base_model -> offset -> a) -> (a -> a -> a) ->
    t -> location -> a or_bottom =
    fun map reduce (state,_tracked) loc ->
    let f base off acc =
      let v = map (fst (MemoryMap.find_or_top state base)) off in
      Bottom.join reduce (`Value v) acc
    in
    Location.fold f loc `Bottom

  let get ~oracle (state : t) (src : location) : value or_bottom =
    let oracle = convert_oracle oracle in
    read (BaseModel.get ~oracle) Value.join state src

  let extract ~oracle (state : t) (src : location) : BaseModel.t or_bottom =
    let oracle = convert_oracle oracle in
    read (BaseModel.extract ~oracle) (BaseModel.smash ~oracle) state src

  let write'
      (update : base_model -> offset -> base_model or_bottom)
      (state : t) (loc : location) : t or_bottom =
    let deps = List.map Base.of_varinfo (Location.references loc) in
    let deps_set = Tracking.of_list deps in
    let f base off state' =
      let* base_map,tracked = state' in
      if covers_base tracked base then
        let memory, refs = MemoryMap.find_or_top base_map base in
        let+ memory' = update memory off in
        MemoryMap.add base (memory', refs) base_map,
        Option.map (Tracking.union deps_set) tracked
      else
        state'
    in
    let+ state = Location.fold f loc (`Value state) in
    add_references_l state deps (Location.bases loc)

  let write update state loc =
    (* Result can never be bottom if update never returns bottom *)
    Bottom.non_bottom (write' (fun m o -> `Value (update m o)) state loc)

  let set ~oracle (state : t) (dst : location) (v : value) : t =
    let weak = not (Location.is_singleton ~oracle dst) in
    let oracle = convert_oracle oracle in
    write (BaseModel.set ~oracle ~weak v) state dst

  let replace ~oracle (state : t) (dst : location) (src : location) : t =
    match extract ~oracle state src with
    | `Bottom -> state (* no source *)
    | `Value value ->
      let weak = not (Location.is_singleton ~oracle dst) in
      let oracle = convert_oracle oracle in
      write (fun m off -> BaseModel.replace ~oracle ~weak m off value) state dst

  let erase ~oracle ?(weak: bool option)
      (state : t) (dst : location) (b : Abstract_memory.bit) : t =
    let weak = match weak with
      | None -> not (Location.is_singleton ~oracle dst)
      | Some weak -> weak
    in
    let oracle = convert_oracle oracle in
    write (fun m off -> BaseModel.erase ~oracle ~weak m off b) state dst

  let reinforce
      ~oracle
      (f : value -> value or_bottom)
      (state : t) (dst : location) : t or_bottom =
    let oracle = convert_oracle oracle in
    write' (fun m off -> BaseModel.reinforce ~oracle f m off) state dst

  let remove ~oracle (vi : Cil_types.varinfo) (state : t) =
    let state = update_var_references ~oracle vi None state in
    let map, tracked = state in
    MemoryMap.remove (Base.of_varinfo vi) map, tracked

  let project bases (base_map, tracked : t) =
    MemoryMap.inter_with_shape bases base_map,
    Option.map (Tracking.inter bases) tracked

  (* Lattice *)

  let top = MemoryMap.empty, None

  let is_included =
    let open MemoryMap in
    let cache = cache_name "is_included" in
    let decide_fst _b _v1 = true (* v2 is top *) in
    let decide_snd _b _v2 = false (* v1 is top, v2 is not *) in
    let decide_both _ (m1,_r1) (m2,_r2) = BaseModel.is_included m1 m2 in
    let decide_fast s t = if s == t then PTrue else PUnknown in
    let is_included = binary_predicate cache UniversalPredicate
        ~decide_fast ~decide_fst ~decide_snd ~decide_both
    in
    fun (m1, _) (m2, _) -> is_included m1 m2

  let narrow =
    let open MemoryMap in
    let cache = cache_name "narrow" in
    let decide _ v1 v2 = BaseModel.narrow v1 v2 in
    let narrow = join ~cache ~symmetric:false ~idempotent:true ~decide in
    fun (m1,t1) (m2,t2) ->
      `Value (narrow m1 m2, Option.merge Tracking.union t1 t2)

  (* Precise join with oracle, but cannot be cached. *)
  let precise_join ~oracle m1 m2 =
    let open MemoryMap in
    let cache = Hptmap_sig.NoCache
    and decide _ x1 x2 =
      let m1,r1 = Option.value ~default:Map_value.top x1
      and m2,r2 = Option.value ~default:Map_value.top x2 in
      BaseModel.join ~oracle m1 m2, Referers.union r1 r2 (* TODO: Remove tops *)
    in
    generic_join ~cache ~symmetric:false ~idempotent:true ~decide m1 m2

  (* Optimized join without oracle. *)
  let fast_join =
    let open MemoryMap in
    let oracle _ _ = Int_val.top in
    let cache = cache_name "fast_join"
    and decide _ x1 x2 =
      let m1, r1 = Option.value ~default:Map_value.top x1
      and m2, r2 = Option.value ~default:Map_value.top x2 in
      BaseModel.join ~oracle m1 m2, Referers.union r1 r2 (* TODO: Remove tops *)
    in
    generic_join ~cache ~symmetric:true ~idempotent:true ~decide

  let join ~oracle (m1, t1) (m2, t2) =
    let m =
      if Parameters.MultidimFastImprecise.get ()
      then fast_join m1 m2
      else precise_join ~oracle m1 m2
    in
    m, Option.merge Tracking.union t1 t2

  let widen ~oracle kf stmt (m1,t1) (m2,t2) =
    let open MemoryMap in
    let  _,get_hints = Widen.getWidenHints kf stmt in
    let cache = Hptmap_sig.NoCache
    and decide base x1 x2 =
      let m1,r1 = Option.value ~default:Map_value.top x1
      and m2,r2 = Option.value ~default:Map_value.top x2 in
      BaseModel.widen ~oracle (get_hints base) m1 m2, Referers.union r1 r2
    in
    generic_join ~cache ~symmetric:false ~idempotent:true ~decide m1 m2,
    Option.merge Tracking.union t1 t2

  let overwrite =
    let cache = cache_name "overwrite_bases" in
    let decide _key _v1 v2 = v2 in
    let join = MemoryMap.join ~cache ~symmetric:false ~idempotent:true ~decide in
    fun (bases : Base.Hptset.t) ~on:(m1, t1 : t) ~by:(m2, t2 : t) ->
      let m1 = MemoryMap.diff_with_shape bases m1 in
      join m1 m2, Option.merge Tracking.union t1 t2

  (* Iterators *)

  let map (f : location -> value -> value) (m, t : t) : t =
    let f base o v = f (Location.singleton base o) v in
    let f base (m, t) = Some (BaseModel.map (f base) m, t) in
    (MemoryMap.filter_map f m, t)

  let iter (f : location -> value -> unit) (m,_ : t) : unit =
    let f base o v = f (Location.singleton base o) v in
    let f base (m, _) = BaseModel.iter (f base) m in
    MemoryMap.iter f m

  let fold (f : location -> value -> 'a -> 'a) (m,_ : t) (acc :'a) : 'a =
    let f base o v acc = f (Location.singleton base o) v acc in
    let f base (m, _) acc = BaseModel.fold (f base) m acc in
    MemoryMap.fold f m acc

  let filter (f : location -> value -> bool) (m, t : t) : t =
    let f' base (m, t) =
      if BaseModel.for_all (fun o v -> f (Location.singleton base o) v) m
      then Some (m, t)
      else None
    in
    (MemoryMap.filter_map f' m, t)
end


(* --- Generic Domain Functor --- *)

module Make_Generic_Domain
    (Params : sig val name : string end)
    (Value : GenericValue)
    (CellValue : CellValue with type value = Value.t) =
struct
  module Model = Make_Generic_Memory (CellValue)

  let value_dependencies = Value.dependencies
  let location_dependencies = Main_locations.ploc

  type state = Model.t

  let find_builtin =
    let module Table = Stdlib.Hashtbl in
    let table = Table.create 17 in
    List.iter (fun (name, f) -> Table.replace table name f) Value.builtins;
    fun kf ->
      try Some (Table.find table (Kernel_function.get_name kf))
      with Not_found -> None

  let mk_oracle (state : state) =
    let open Bottom.Operators in
    let get ~oracle lval =
      match Location.of_lval ~oracle lval with
      | `Top -> `Value Cvalue.V.top
      | `Value loc -> Model.get ~oracle state loc >>-: CellValue.to_cvalue
    in default_oracle get

  let mk_bioracle s1 s2 =
    let oracle_left = mk_oracle s1
    and oracle_right = mk_oracle s2 in
    function
    | Abstract_memory.Left -> convert_oracle oracle_left
    | Right -> convert_oracle oracle_right


  module Prototype = struct
    include Model
    let name = Params.name
  end

  include Domain_builder.Complete (Prototype)
  include Prototype

  type value = Value.t
  type location = Precise_locs.precise_location (* should be Location.t *)
  type origin

  (* Lattice *)

  let join s1 s2 =
    let oracle = mk_bioracle s1 s2 in
    join ~oracle s1 s2

  let widen kf stmt s1 s2 =
    let oracle = mk_bioracle s1 s2 in
    widen ~oracle kf stmt s1 s2

  (* Eva Queries *)

  (* Nothing interesting to be done on expressions *)
  let extract_expr ~oracle:_ _context _state _expr =
    `Value (Value.top, None), Alarmset.all

  let extract_lval ~oracle _context state lv _loc =
    if Ast_types.C.is_scalar lv.Eva_ast.typ then
      let oracle = fun exp ->
        match oracle exp with
        (* only use values safely evaluated *)
        | `Value v, alarms when Alarmset.is_empty alarms -> Value.to_cvalue v
        | _ -> Cvalue.V.top
      in
      match Location.of_lval ~oracle lv with
      | `Top -> (* can't evaluate location *)
        `Value (Value.top, None), Alarmset.all
      | `Value loc ->
        match Model.get ~oracle state loc with
        | `Bottom -> `Bottom, Alarmset.all
        | `Value v ->
          let r =
            let+ v = CellValue.to_value v in v, None
          and alarms =
            if CellValue.is_initialized v
            then
              let origin = Eva_ast.to_cil_lval lv in
              Alarmset.(set (Alarms.Uninitialized origin) True all)
            else Alarmset.all
          in r, alarms
    else
      `Value (Value.top, None), Alarmset.all


  (* Eva Transfer *)

  let valuation_to_oracle state valuation : Eva_ast.exp -> Cvalue.V.t =
    fun exp ->
    let memory_oracle = mk_oracle state in
    match valuation.Abstract_domain.find exp with
    | `Top -> memory_oracle exp
    | `Value {value={v=`Bottom}} -> Cvalue.V.bottom
    | `Value {value={v=`Value value}} -> Value.to_cvalue value

  let assume_exp valuation expr record state' =
    let* state = state' in
    let oracle = valuation_to_oracle state valuation in
    match (expr : Eva_ast.exp).node with
    | Lval lv when Ast_types.C.is_scalar lv.typ ->
      let value = CellValue.of_flagged record.value in
      if not (CellValue.is_topint value) then
        match Location.of_lval ~oracle lv with
        | `Top -> `Value state (* location evaluate to top, ignore *)
        | `Value loc ->
          let update value' =
            let v = CellValue.narrow value value' in
            (* The value can legitimately be bottom on escaping variables,
                which are not tracked by the cell memories.
                In this case, do not reduce the state to bottom. *)
            if Bottom.is_bottom v && record.value.escaping
            then `Value CellValue.bottom
            else v
          in
          if Location.is_singleton ~oracle loc
          then Model.reinforce ~oracle update state loc
          else `Value state
      else `Value state
    | _ -> `Value state

  let assume_valuation valuation state =
    valuation.Abstract_domain.fold (assume_exp valuation) (`Value state)

  let update valuation state =
    assume_valuation valuation state

  let assign' ~oracle ~value dst src state =
    match Location.of_lval ~oracle dst with
    | `Top -> Model.top
    | `Value dst ->
      let state = Model.update_references ~oracle dst src state in
      match value with
      | Assign value ->
        Model.set ~oracle state dst (CellValue.of_value value)
      | Copy (right, value) ->
        match Location.of_lval ~oracle right.lval with
        | `Top ->
          let b = CellValue.(to_bit (of_flagged value)) in
          Model.erase ~oracle state dst b
        | `Value src ->
          Model.replace ~oracle state dst src

  let assign ~pos:_ { lval=dst } src assigned_value valuation state =
    if Z_or_top.is_zero (Bit_utils.sizeof dst.typ)
    then `Value state
    else
      let+ state = assume_valuation valuation state in
      let oracle = valuation_to_oracle state valuation in
      assign' ~oracle ~value:assigned_value dst (Some src) state

  let assume ~pos:_ _expr _pos valuation state =
    assume_valuation valuation state

  let start_call ~pos:_ call recursion valuation state =
    if recursion <> None
    then
      Self.abort ~current:true
        "The cell memory model does not support recursive calls yet";
    let oracle = valuation_to_oracle state valuation in
    let bind state arg =
      state >>-:
      assign' ~oracle ~value:arg.avalue (Eva_ast.Build.var arg.formal) (Some arg.concrete)
    in
    List.fold_left bind (`Value state) call.arguments

  let finalize_call ~pos:_ call _recursion ~pre:_ ~post =
    match find_builtin call.kf, call.return with
    | None, _ | _, None   -> `Value post
    | Some f, Some return ->
      let arg_value = fun arg -> value_assigned arg.avalue in
      let* args = Bottom.List.map arg_value call.arguments in
      let+ result = f args in
      let oracle = mk_oracle post in
      let dst = Eva_ast.Build.var return in
      assign' ~oracle ~value:(Assign result) dst None post

  let show_expr valuation state fmt expr =
    match (expr : Eva_ast.exp).node with
    | Lval lval | StartOf lval ->
      let oracle = valuation_to_oracle state valuation in
      begin match Location.of_lval ~oracle lval with
        | `Top -> Unicode.pp_top fmt
        | `Value loc ->
          let m = Model.extract ~oracle state loc in
          Bottom.pretty Model.BaseModel.pretty fmt m
      end
    | _ -> ()

  let enter_scope _kind vars state =
    let oracle = mk_oracle state in
    let enter_one state v =
      let dst = Location.of_var v in
      Model.erase ~oracle state dst Abstract_memory.Bit.uninitialized
    in
    List.fold_left enter_one state vars

  let leave_scope _kf vars state =
    let oracle = mk_oracle state in
    List.fold_left (fun state vi -> Model.remove ~oracle vi state) state vars

  let logic_assign assign location state =
    let oracle = mk_oracle state
    and dst = Location.of_precise_loc location
    and b =
      match assign with
      | None
      | Some (Frees _, _)
      | Some (Allocates _, _)
      | Some (Assigns (_, _ :: _), _) -> Abstract_memory.Bit.top
      | Some (Assigns (_, []), _) -> Abstract_memory.Bit.numerical
    in
    let state = Model.update_references ~oracle dst None state in
    Model.erase ~oracle ~weak:true state dst b

  let reduce_by_papp env li _labels args positive state =
    match li.Cil_types.l_var_info.lv_name, args with
    | "\\are_finite", [arg] ->
      begin match Location.of_term env arg with
        | `Top -> `Value state (* can't resolve location, ignore *)
        | `Value (loc,typ) ->
          begin match Ast_types.(C.unroll_node (Acsl.get_ctype typ)) with
            | TFloat fkind ->
              let update = Value.backward_is_finite positive fkind
              and oracle = mk_oracle state in
              Model.reinforce ~oracle (CellValue.map' update) state loc
            | _ | exception (Failure _) -> `Value state
          end
      end
    | _ -> `Value state

  let reduce_by_predicate env state predicate truth =
    let rec reduce predicate truth state =
      match truth, predicate.Cil_types.pred_content with
      | true, Pand (p1,p2) | false, Por (p1,p2) ->
        state |> reduce p1 truth >>- reduce p2 truth
      | _,Papp (li, labels, args) ->
        reduce_by_papp env li labels args truth state
      | _ -> `Value state
    in
    reduce predicate truth state

  let interpret_acsl_extension extension _env state =
    match extension.Cil_types.ext_name with
    | "array_partition" ->
      let annotation = Eva_annotations.read_array_segmentation extension in
      let vi,offset,bounds = annotation in
      (* Update the segmentation *)
      let bounds = List.map Eva_ast.translate_exp bounds in
      let lval = Eva_ast.translate_lval (Var vi, offset) in
      let oracle = mk_oracle state in
      begin match Location.of_lval ~oracle lval with
        | `Top -> state
        | `Value loc ->
          let update m offset =
            let oracle = convert_oracle oracle in
            Model.BaseModel.segmentation_hint ~oracle m offset bounds
          in
          let state = Model.write update state loc in
          (* Update the references *)
          let add acc e =
            let r = Eva_ast.vars_in_exp e in
            (Cil_datatype.Varinfo.Set.to_seq r |> List.of_seq) @ acc
          in
          let references = List.fold_left add [] bounds in
          let references = List.map Base.of_varinfo references in
          Model.add_references_l state references (Location.bases loc)
      end
    | "eva_domain_scope" ->
      let domain,vars = Eva_annotations.read_domain_scope extension in
      if domain = name then
        let bases = List.map Base.of_varinfo vars in
        Model.set_tracking state bases
      else
        state
    | _ ->
      state

  let empty () = Model.top

  let initialize_variable lval _loc ~initialized:_ init_value state =
    let oracle = mk_oracle state in
    match Location.of_lval ~oracle lval with
    | `Top -> Model.top
    | `Value dst ->
      let d = match init_value with
        | Abstract_domain.Top  -> Abstract_memory.Bit.numerical
        | Abstract_domain.Zero -> Abstract_memory.Bit.zero
      in
      let oracle = mk_oracle state in (* Since dst has no offset, oracle is actually useless *)
      Model.erase ~oracle state dst d

  let initialize_variable_using_type _kind vi state =
    let lval = Eva_ast.Build.var vi in
    let oracle = mk_oracle state in
    match Location.of_lval ~oracle lval with
    | `Top -> Model.top
    | `Value dst ->
      let oracle = mk_oracle state in (* Since dst has no offset, oracle is actually useless *)
      Model.erase ~oracle state dst Abstract_memory.Bit.top

  let relate _bases _state = Base.SetLattice.empty

  let filter = Model.project
  let project = Model.project

  let reuse bases ~current_input ~previous_output =
    Model.overwrite bases ~on:current_input ~by:previous_output

  let join_hook (module Abstract: Abstractions.S) : (module Abstractions.S) =
    match Abstract.Val.get Main_values.CVal.key, Abstract.Dom.get key with
    | None, _
    | _, None -> (module Abstract)
    | Some get_cval, Some get_value ->
      let module Eval =
        Evaluation.Make
          (Abstract.Ctx) (Abstract.Val) (Abstract.Loc) (Abstract.Dom)
      in
      let module Dom = struct
        include Abstract.Dom

        let join a b =
          let r = join (set key Model.top a) (set key Model.top b) in
          let oracle state =
            let valuation_ref = ref Eval.Valuation.empty in
            fun exp ->
              let valuation = !valuation_ref in
              let v, _alarms = Eval.evaluate ~valuation state exp in
              match v with
              | `Bottom -> Cvalue.V.top
              | `Value (valuation, v) ->
                valuation_ref := valuation;
                get_cval v
          in
          let left_oracle = oracle a
          and right_oracle = oracle b in
          let oracle = function
            | Abstract_memory.Left ->  convert_oracle left_oracle
            | Abstract_memory.Right -> convert_oracle right_oracle
          in
          let state = Model.join ~oracle (get_value a) (get_value b) in
          set key state r
      end
      in
      (module struct
        module Ctx = Abstract.Ctx
        module Val = Abstract.Val
        module Loc = Abstract.Loc
        module Dom = Dom
      end)

  let () = Abstractions.Hooks.register join_hook
end


(** --- Instantiation of the multidim domain --- *)

module CValue =
struct
  type t = Cvalue.V.t
  let top = Cvalue.V.top
  let to_cvalue v = v
  let builtins = []
  let dependencies = Abstract_value.Leaf (module Main_values.CVal)

  let backward_is_finite positive fkind v =
    let open Cvalue.V in
    let prec = Fval.kind fkind in
    try
      let v = reinterpret_as_float fkind v in
      Fval.backward_is_finite ~positive prec (project_float v) >>-: inject_float
    with Not_based_on_null ->
      `Value v
end

module CvalueOrUninitialized =
struct
  include Cvalue.V_Or_Uninitialized
  module V = Cvalue.V

  type value = V.t

  let widen ~size ~hint =
    widen ~size ~hint

  let narrow v1' v2' =
    let r = narrow v1' v2' in
    if is_bottom r then `Bottom else `Value r

  let to_integer v' =
    try  Some (Ival.project_int (V.project_ival (get_v v')))
    with V.Not_based_on_null | Ival.Not_Singleton_Int -> None

  let to_value v' =
    let v = get_v v' in
    if V.is_bottom v
    then `Bottom
    else `Value v

  let to_cvalue v' =
    get_v v'

  let of_flagged fv =
    make
      ~initialized:fv.initialized
      ~escaping:false
      (Bottom.value ~bottom:V.bottom fv.v)

  let of_value v =
    make ~initialized:true ~escaping:false v

  let make i v =
    let initialized = match i with
      | Abstract_memory.SurelyInitialized -> true
      | Abstract_memory.MaybeUninitialized -> false
    in
    make ~initialized ~escaping:false v

  let of_bit ~typ:_ = function
    | Abstract_memory.Uninitialized -> uninitialized
    | Zero i -> make i (V.inject_int Z.zero)
    | Any (Top, i) -> make i (V.top_with_origin Origin.unknown)
    | Any (Set s, i) ->
      let v =
        if Base.Hptset.is_empty s
        then V.inject_ival Ival.top
        else V.inject_top_origin Origin.unknown s
      in
      make i v

  let to_bit v' =
    match to_value v' with
    | `Bottom -> Abstract_memory.Uninitialized
    | `Value v ->
      let initialization =
        if is_initialized v'
        then Abstract_memory.SurelyInitialized
        else Abstract_memory.MaybeUninitialized
      in
      if V.is_zero v
      then Abstract_memory.Zero (initialization)
      else Abstract_memory.Any (V.get_bases v, initialization)

  let is_topint v' =
    get_v v' |> V.is_topint

  let map' f v' =
    let+ new_v = f (get_v v') in
    map (fun _ -> new_v) v'
end

module MultidimDomain =
  Make_Generic_Domain
    (struct let name = "multidim" end)
    (CValue)
    (CvalueOrUninitialized)

(* Registers the domain. *)
let registered =
  let name = "multidim"
  and descr = "Improve the precision over arrays of structures \
               or multidimensional arrays."
  in
  Abstractions.Domain.register ~name ~descr ~experimental:true ~priority:7
    (module MultidimDomain)


(** --- Simplified memory model's functor --- *)

module type Lattice = sig
  include Datatype.S
  val top : t
  val is_included : t -> t -> bool
  val join : t -> t -> t
  val narrow : t -> t -> t or_bottom
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
end

module Make_Generic_Cell_Value (Value : Lattice) =
struct
  open Bottom.Operators

  include Datatype.Pair (CvalueOrUninitialized) (Value)
  type value = Cvalue.V.t * Value.t

  let pretty fmt v = snd v |> Value.pretty fmt
  let to_bit v = fst v |> CvalueOrUninitialized.to_bit
  let to_integer v = fst v |> CvalueOrUninitialized.to_integer

  let of_bit ~typ b =
    CvalueOrUninitialized.of_bit ~typ b,
    match b with
    | Abstract_memory.Zero _ -> Value.zero
    | Any _ | Uninitialized -> Value.top

  let top = CvalueOrUninitialized.top, Value.top
  let bottom = CvalueOrUninitialized.bottom, Value.top

  let is_included (cv1, v1) (cv2, v2) =
    CvalueOrUninitialized.is_included cv1 cv2 &&
    Value.is_included v1 v2

  let join (cv1, v1) (cv2, v2) =
    CvalueOrUninitialized.join cv1 cv2,
    Value.join v1 v2

  let narrow (cv1, v1) (cv2, v2) =
    let+ cv = CvalueOrUninitialized.narrow cv1 cv2
    and+ v = Value.narrow v1 v2 in
    cv, v

  let widen ~size ~hint (cv1, v1) (cv2, v2) =
    CvalueOrUninitialized.widen ~size ~hint cv1 cv2,
    Value.widen ~size ~hint v1 v2

  let is_topint v = fst v |> CvalueOrUninitialized.is_topint
  let is_bottom v = fst v |> CvalueOrUninitialized.is_bottom
  let is_initialized v = fst v |> CvalueOrUninitialized.is_initialized
  let to_cvalue v = fst v |> CvalueOrUninitialized.to_cvalue
  let to_value (cv, v) = let+ cv' = CvalueOrUninitialized.to_value cv in cv', v
  let of_value v = fst v |> CvalueOrUninitialized.of_value, snd v

  let of_flagged (fv : value Eval.flagged_value) : t =
    CvalueOrUninitialized.of_flagged { fv with v = Bottom.map fst fv.v },
    Bottom.value ~bottom:Value.top (let+ (_cv, v) = fv.v in v)

  let map' (f  : (value -> value or_bottom)) (cv,v : t) : t or_bottom =
    let* (cv',v') = to_value (cv,v) in
    let+ (cv'',v'') = f (cv',v') in
    CvalueOrUninitialized.map (fun _ -> cv'') cv, v''
end

module Make_Memory (Value : Lattice) =
struct
  open Bottom.Operators
  module CellValue = Make_Generic_Cell_Value (Value)
  module Model = Make_Generic_Memory (CellValue)
  include Model

  type oracle = Cell_oracle.oracle

  let mk_oracle (memory : t) =
    let get ~oracle lval =
      match Location.of_lval ~oracle lval with
      | `Top -> `Value Cvalue.V.top
      | `Value loc -> Model.get ~oracle memory loc >>-: CellValue.to_cvalue
    in default_oracle get

  let mk_bioracle s1 s2 =
    let oracle_left = mk_oracle s1
    and oracle_right = mk_oracle s2 in
    function
    | Abstract_memory.Left -> convert_oracle oracle_left
    | Right -> convert_oracle oracle_right

  let remove_references ?oracle base memory =
    let oracle = Option.(oracle <? mk_oracle memory) in
    Model.remove_base_references ~oracle base memory

  let update_references ?oracle location exp memory =
    let oracle = Option.(oracle <? mk_oracle memory) in
    Model.update_references ~oracle location exp memory

  let reinforce ?oracle f memory loc =
    let open Bottom.Operators in
    let oracle = Option.(oracle <? mk_oracle memory) in
    let f' (cv, v) =
      let+ (cv', v') = f (CvalueOrUninitialized.to_cvalue cv, v) in
      CvalueOrUninitialized.of_value cv', v'
    in Model.reinforce ~oracle f' memory loc

  let join l r =
    let oracle = mk_bioracle l r in
    Model.join ~oracle l r

  let widen kf stmt l r =
    let oracle = mk_bioracle l r in
    Model.widen ~oracle kf stmt l r

  let get ?oracle m loc =
    let open Bottom.Operators in
    let oracle = Option.(oracle <? mk_oracle m) in
    let* cv_u, v = Model.get ~oracle m loc in
    let is_initialized = CvalueOrUninitialized.is_initialized cv_u in
    if CvalueOrUninitialized.is_bottom cv_u then `Bottom
    else `Value (CvalueOrUninitialized.get_v cv_u, v, is_initialized)

  let read ?oracle memory loc =
    match get ?oracle memory loc with
    | `Bottom -> assert false
    | `Value (_, v, _) -> v

  let set ?oracle m loc c v =
    let oracle = Option.(oracle <? mk_oracle m) in
    let c = CvalueOrUninitialized.of_value c in
    Model.set ~oracle m loc (c, v)

  let remove ?oracle var memory =
    let oracle = Option.(oracle <? mk_oracle memory) in
    Model.remove ~oracle var memory

  let replace ?oracle memory =
    let oracle = Option.(oracle <? mk_oracle memory) in
    Model.replace ~oracle memory

  let erase ?oracle ?weak memory loc b =
    let oracle = Option.(oracle <? mk_oracle memory) in
    Model.erase ~oracle ?weak memory loc b

  let iter f state =
    let f' loc (_,v) = f loc v in
    iter f' state

  let fold f state acc =
    let f' loc (_,v) acc = f loc v acc in
    fold f' state acc

  let map f state =
    let f' loc (c, v) = (c, f loc v) in
    map f' state

  let filter f state =
    let f' loc (_, v) = f loc v in
    filter f' state
end


(** --- Simplified domain instantiation --- **)

module type Value =
sig
  include Abstract_value.Leaf
  val zero : t
  val widen : size:Z.t -> hint:Ival.widen_hint ->  t -> t -> t
  val builtins: (string * t builtin) list
end

module Make_Generic_Value (Value : Value) =
struct
  open Bottom.Operators

  type t = Cvalue.V.t * Value.t
  let top = (Cvalue.V.top, Value.top)
  let to_cvalue = fst

  let builtins =
    let topify v = (Cvalue.V.top, v) in
    let lift f args = List.map snd args |> f |> Bottom.map topify in
    List.map (fun (name, f) -> name, lift f) Value.builtins

  let dependencies =
    let cvalue = Abstract_value.Leaf (module Main_values.CVal) in
    let value = Abstract_value.Leaf (module Value) in
    Abstract_value.Node (cvalue, value)

  let backward_is_finite pos fkind (cv, v) =
    let+ cv' = CValue.backward_is_finite pos fkind cv in cv', v
end

module Make (Params : sig val name : string end) (Value : Value) =
struct
  module GenericValue = Make_Generic_Value (Value)
  module GenericCellValue = Make_Generic_Cell_Value (Value)
  include Make_Generic_Domain (Params) (GenericValue) (GenericCellValue)
end
