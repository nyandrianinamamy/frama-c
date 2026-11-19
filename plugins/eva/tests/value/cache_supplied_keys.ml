(* Test module of cache_supplied_keys.c: supplies an entry with two exit
   states of different partition keys, and the Reach part of an analysis of
   the body, runs the analysis, then prints the entry. *)

open Cil_types

module Supplied = Eva.Supplied_entries

let state bindings =
  let bind acc (vi, v) =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    let v = Cvalue.V_Or_Uninitialized.initialized v in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size acc
  in
  List.fold_left bind Cvalue.Model.empty_map bindings

module Reach = Eva.Reach_part

(* The Reach part of an analysis of choose from the input of the entry,
   written by hand: the four statements of choose are reached, and both
   branches of the condition at line 28 are taken. *)
let reach kf ~choice ~out =
  let line s = Filepos.line (Fileloc.start_pos (Cil_datatype.Stmt.loc s)) in
  let stmt is_kind l =
    List.find (fun s -> line s = l && is_kind s.skind)
      (Kernel_function.get_definition kf).sallstmts
  in
  let cond = stmt (function If _ -> true | _ -> false) 28 in
  let set l = stmt (function Instr (Set _) -> true | _ -> false) l in
  let return = stmt (function Return _ -> true | _ -> false) 30 in
  let point p = Reach.Reached { point = p; frames = [] } in
  let reached s =
    [ point (Eva__Domain_store.Before s); point (Eva__Domain_store.After s) ]
  in
  let zones stmt ~read ~write =
    let zone = function
      | None -> Memory_zone.bottom
      | Some vi -> Locations.zone_of_varinfo vi
    in
    Reach.Zones { stmt; frames = []; read = zone read; write = zone write }
  in
  Reach.part ~points:true
    (List.concat_map reached [ cond; set 28; set 29; return ]
     @ [ Reach.Guard { stmt = cond; outcome = true };
         Reach.Guard { stmt = cond; outcome = false };
         zones cond ~read:(Some choice) ~write:None;
         zones (set 28) ~read:None ~write:(Some out);
         zones (set 29) ~read:None ~write:(Some out) ])

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
    Supplied.supply ~reach:(reach kf ~choice ~out) kf
      ~key:(bases [choice])
      ~input:(state [choice, Cvalue.V.top_int])
      ~footprint:{ read = bases [choice]; written = bases [out];
                   written_exit = bases [out]; written_sure = bases [out] }
      ~exit:[ exit 0 1; exit 1 2 ]
  in
  Eva.Analysis.compute ();
  Kernel.result "%a" Supplied.pretty entry

let () = Boot.Main.extend run
