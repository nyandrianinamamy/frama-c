(* Test module of cache_supplied_keys.c: supplies an entry with two exit
   states of different partition keys, runs the analysis, then prints the
   entry. *)

open Cil_types

module Supplied = Eva.Supplied_entries

let state bindings =
  let bind acc (vi, v) =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    let v = Cvalue.V_Or_Uninitialized.initialized v in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size acc
  in
  List.fold_left bind Cvalue.Model.empty_map bindings

let run () =
  let kf = Globals.Functions.find_by_name "choose" in
  let global name = Globals.Vars.find_from_astinfo name Global in
  let choice = global "choice" and out = global "out" in
  let bases l = Base.Hptset.of_list (List.map Base.of_varinfo l) in
  let int n = Cvalue.V.inject_int (Z.of_int n) in
  let exit rank n =
    Supplied.case_key kf rank, state [choice, Cvalue.V.top_int; out, int n]
  in
  let entry =
    Supplied.supply kf
      ~key:(bases [choice])
      ~input:(state [choice, Cvalue.V.top_int])
      ~footprint:{ read = bases [choice]; written = bases [out];
                   written_exit = bases [out]; written_sure = bases [out] }
      ~exit:[ exit 0 1; exit 1 2 ]
  in
  Eva.Analysis.compute ();
  Kernel.result "%a" Supplied.pretty entry

let () = Boot.Main.extend run
