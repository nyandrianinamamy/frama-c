(* Test module of cache_supplied.c: supplies cache entries to the reuse
   operation, runs the analysis, then reads the entries and the counts. *)

open Cil_types

module Supplied = Eva.Supplied_entries

let kf name = Globals.Functions.find_by_name name

let global name = Globals.Vars.find_from_astinfo name Global

let formal f name =
  List.find (fun vi -> vi.vname = name) (Kernel_function.get_formals (kf f))

let bases vis =
  List.fold_left
    (fun acc vi -> Base.Hptset.add (Base.of_varinfo vi) acc)
    Base.Hptset.empty vis

(* A cvalue state in which each variable is initialized to its value. *)
let state bindings =
  let bind acc (vi, v) =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    let v = Cvalue.V_Or_Uninitialized.initialized v in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size acc
  in
  List.fold_left bind Cvalue.Model.empty_map bindings

let int n = Cvalue.V.inject_int (Z.of_int n)

let range a b =
  let ival = Ival.inject_range (Some (Z.of_int a)) (Some (Z.of_int b)) in
  Cvalue.V.inject_ival ival

let supply () =
  let g = global "g" and out = global "out" and keep = global "keep" in
  (* Entry 1, for step: key {x, g} with x = 1 and g = 3; writes out = 4. *)
  let x = formal "step" "x" in
  ignore
    (Supplied.supply (kf "step")
       ~key:(bases [x; g])
       ~input:(state [x, int 1; g, int 3])
       ~footprint:{ read = bases [x; g]; written = bases [out] }
       ~exit:[ state [x, int 1; g, int 3; out, int 4] ]);
  (* Entry 2, for set_out: empty key; writes out = 7. The supplied exit state
     also binds keep to 0, a block outside the key and the written set. *)
  ignore
    (Supplied.supply (kf "set_out")
       ~key:Base.Hptset.empty
       ~input:Cvalue.Model.empty_map
       ~footprint:{ read = bases [keep]; written = bases [out] }
       ~exit:[ state [out, int 7; keep, int 0] ]);
  (* Entries 3 and 4, for precise_first, then entries 5 and 6, for
     wide_first: two candidates with the same key, x = 1, one exit out = 7
     and the other out in [7..8]. They are supplied in opposite orders. *)
  let two name ~first ~second =
    let x = formal name "x" in
    let entry v =
      ignore
        (Supplied.supply (kf name)
           ~key:(bases [x])
           ~input:(state [x, int 1])
           ~footprint:{ read = bases [x]; written = bases [out] }
           ~exit:[ state [x, int 1; out, v] ])
    in
    entry first;
    entry second
  in
  two "precise_first" ~first:(int 7) ~second:(range 7 8);
  two "wide_first" ~first:(range 7 8) ~second:(int 7);
  (* An exit state that does not bind the written block out is refused, and
     no entry is added. *)
  match
    Supplied.supply (kf "set_out")
      ~key:Base.Hptset.empty
      ~input:Cvalue.Model.empty_map
      ~footprint:{ read = Base.Hptset.empty; written = bases [out] }
      ~exit:[ state [keep, int 0] ]
  with
  | _ -> Kernel.result "entry supplied with an exit state that misses out"
  | exception Invalid_argument msg -> Kernel.result "refused: %s" msg

let print_entries name =
  List.iter
    (fun e -> Kernel.result "entry of %s: %a" name Supplied.pretty e)
    (Supplied.entries (kf name))

(* The counts of a function, by name of statistic. *)
let print_counts name =
  let kf = kf name in
  let count (stat, id) =
    Format.asprintf "%s %d" id (Eva.Statistics.get stat kf)
  in
  let rejected reason =
    Eva.Statistics.cache_rejected reason, "cache-rejected-" ^ reason
  in
  let stats =
    [ Eva.Statistics.cache_hits, "cache-hits";
      rejected "key-differs"; rejected "key-unclosed";
      rejected "product"; rejected "consumer";
      Eva.Statistics.cache_refused "supplied-only",
      "cache-refused-supplied-only";
      Eva.Statistics.memexec_hits, "memexec-hits";
      Eva.Statistics.memexec_stored, "memexec-stored" ]
  in
  Kernel.result "@[<hov 2>counts of %s:@ %a@]" name
    (Pretty_utils.pp_list ~sep:",@ " Format.pp_print_string)
    (List.map count stats)

(* The entry of set_out holds no binding for keep: the exit states of an
   entry are filtered to its key and its written blocks. *)
let check_frame () =
  let keep = Base.of_varinfo (global "keep") in
  let binds_keep (_, s) =
    match Cvalue.Model.find_base keep s with
    | `Value _ -> true
    | `Bottom | `Top -> false
    | exception Not_found -> false
  in
  List.iter
    (fun e ->
       Kernel.result "exit of set_out binds keep: %b"
         (List.exists binds_keep (Supplied.exit e)))
    (Supplied.entries (kf "set_out"))

let run () =
  supply ();
  Eva.Analysis.compute ();
  let functions =
    [ "step"; "set_out"; "precise_first"; "wide_first"; "plain" ]
  in
  List.iter print_entries functions;
  check_frame ();
  List.iter print_counts functions

let () = Boot.Main.extend run
