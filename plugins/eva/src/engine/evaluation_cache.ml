(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** {2 Cache Building argument} *)

module type T = sig
  type value
  type origin
  type loc
  type val_report
  type loc_report

  val default_val_report : val_report
  val default_loc : loc
end

(** {2 Cache Building Functor} *)

module Make (T : T) = struct

  include T

  type exp = Eva_ast.exp
  type lval = Eva_ast.lval

  type val_record = (value, origin) Eval.record_val
  type loc_record = loc Eval.record_loc

  type val_entry = val_record * val_report
  type loc_entry = loc_record * loc_report

  (** {3 Persistent map to store evaluation results } *)

  module EvalMap = struct
    module EMap = Eva_ast.Exp.Map
    module LMap = Eva_ast.Lval.Map

    type t =
      { vals: val_entry EMap.t;
        locs: loc_entry LMap.t;
      }

    let empty : t =
      { vals = EMap.empty;
        locs = LMap.empty
      }

    let find_val (exp : exp) (map : t) : val_entry =
      EMap.find exp map.vals

    let find_loc (lval : lval) (map : t) : loc_entry =
      LMap.find lval map.locs

    let add_val (exp : exp) (entry : val_entry) (map : t) : t =
      { map with vals = EMap.add exp entry map.vals }

    let add_loc (lval : lval) (entry : loc_entry) (map : t) : t =
      { map with locs = LMap.add lval entry map.locs }

    let remove_val (exp : exp) (map : t) : t =
      { map with vals = EMap.remove exp map.vals }

    let remove_loc (lval : lval) (map : t) : t =
      { map with locs = LMap.remove lval map.locs }

    let fold_val (f : exp -> val_entry -> 'a -> 'a) (map : t) (acc : 'a) : 'a =
      EMap.fold f map.vals acc
  end

  (** {3 Evaluation map exported as Eval.Valuation } *)

  module Valuation = struct
    type value = T.value
    type origin = T.origin
    type loc = T.loc
    type t = EvalMap.t

    let empty = EvalMap.empty

    let find map exp =
      try `Value (EvalMap.find_val exp map |> fst)
      with Not_found -> `Top

    let find_loc map lval =
      try `Value (EvalMap.find_loc lval map |> fst)
      with Not_found -> `Top

    let find_loc_def map lval =
      try
        let record, _ = EvalMap.find_loc lval map in
        record.loc
      with Not_found -> default_loc

    let add map exp record =
      EvalMap.add_val exp (record, default_val_report) map

    let remove map exp =
      EvalMap.remove_val exp map

    let remove_loc map lval =
      EvalMap.remove_loc lval map

    let fold f map acc =
      EvalMap.fold_val (fun e (r, _) acc -> f e r acc) map acc
  end

  (** {3 Mutable cache } *)

  type valuation = EvalMap.t
  type t = valuation ref

  let create () =
    ref EvalMap.empty

  let find_val cache exp =
    EvalMap.find_val exp !cache

  let find_loc cache lval =
    EvalMap.find_loc lval !cache

  let add_val cache exp entry =
    cache := EvalMap.add_val exp entry !cache

  let add_loc cache lval entry =
    cache := EvalMap.add_loc lval entry !cache

  let remove_val cache exp =
    cache := EvalMap.remove_val exp !cache

  let remove_loc cache lval =
    cache := EvalMap.remove_loc lval !cache
end
