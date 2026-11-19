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

(* The footprint with read blocks [read] and written blocks [written]. By
   default, every written block is written on a path that reaches an exit,
   and surely overwritten. *)
let footprint ?written_exit ?written_sure read written =
  let written = bases written in
  let written_exit = Option.fold ~none:written ~some:bases written_exit in
  let written_sure = Option.fold ~none:written_exit ~some:bases written_sure in
  Supplied.{ read = bases read; written; written_exit; written_sure }

(* A cvalue state in which each variable is initialized to its value. *)
let state bindings =
  let bind acc (vi, v) =
    let size = Z.of_int (Cil.bitsSizeOf vi.vtype) in
    let v = Cvalue.V_Or_Uninitialized.initialized v in
    Cvalue.Model.add_base_value (Base.of_varinfo vi) ~size v ~size_v:size acc
  in
  List.fold_left bind Cvalue.Model.empty_map bindings

(* One exit state, with the partition key of a state that no partitioning
   distinguishes. *)
let one_exit bindings = [ Supplied.empty_key, state bindings ]

let int n = Cvalue.V.inject_int (Z.of_int n)

let range a b =
  let ival = Ival.inject_range (Some (Z.of_int a)) (Some (Z.of_int b)) in
  Cvalue.V.inject_ival ival

let address_of vi = Cvalue.V.inject (Base.of_varinfo vi) Ival.zero

(* ----- Reach parts written by hand ---------------------------------------- *)

module Reach = Eva.Reach_part

let line_of stmt =
  Filepos.line (Fileloc.start_pos (Cil_datatype.Stmt.loc stmt))

(* The statement of the body of [f] at [line], of kind [kind]. *)
let stmt f kind line =
  let is_kind s =
    match kind, s.skind with
    | `Call, Instr (Call _) | `Set, Instr (Set _) | `If, If _
    | `Loop, Loop _ | `Return, Return _ -> true
    | _ -> false
  in
  List.find (fun s -> line_of s = line && is_kind s)
    (Kernel_function.get_definition (kf f)).sallstmts

let zone vis =
  let add z vi = Memory_zone.join z (Locations.zone_of_varinfo vi) in
  List.fold_left add Memory_zone.bottom vis

(* The Reach part of an analysis of a body from the input of its entry, as
   the analysis records it: [stmts] are the statements reached, each before
   and after it, [guards] the branches taken, and [zones] the variables
   read and written at a statement. The body calls no function: no write
   has frames. *)
let by_hand ?(guards = []) ~zones stmts =
  let reached s =
    [ Reach.Reached { point = Eva__Domain_store.Before s; frames = [] };
      Reach.Reached { point = Eva__Domain_store.After s; frames = [] } ]
  in
  let guard (stmt, outcome) = Reach.Guard { stmt; outcome } in
  let access (stmt, read, write) =
    Reach.Zones { stmt; frames = []; read = zone read; write = zone write }
  in
  Reach.part ~points:true
    (List.concat_map reached stmts @ List.map guard guards
     @ List.map access zones)

let supply () =
  let g = global "g" and out = global "out" and keep = global "keep"
  and b = global "b" and choice = global "choice" and p = global "p" in
  (* Entry 1, for step: key {x, g} with x = 1 and g = 3; writes out = 4.
     Each entry carries the Reach part of an analysis of its body from its
     input, written by hand. *)
  let x = formal "step" "x" in
  let call = stmt "step" `Call 62 and set = stmt "step" `Set 63 in
  let reach =
    by_hand [ call; set; stmt "step" `Return 64 ]
      ~zones:[ call, [x; g], []; set, [x; g], [out] ]
  in
  ignore
    (Supplied.supply ~reach (kf "step")
       ~key:(bases [x; g])
       ~input:(state [x, int 1; g, int 3])
       ~footprint:(footprint [x; g] [out])
       ~exit:(one_exit [x, int 1; g, int 3; out, int 4]));
  (* Entry 2, for set_out: empty key; reads nothing and writes out = 7. The
     producer starts with keep = 0 and its exit state keeps it: keep is
     outside the key and the written set. *)
  let call = stmt "set_out" `Call 67 and set = stmt "set_out" `Set 68 in
  let reach =
    by_hand [ call; set; stmt "set_out" `Return 69 ]
      ~zones:[ call, [], []; set, [], [out] ]
  in
  ignore
    (Supplied.supply ~reach (kf "set_out")
       ~key:Base.Hptset.empty
       ~input:(state [keep, int 0])
       ~footprint:(footprint [] [out])
       ~exit:(one_exit [out, int 7; keep, int 0]));
  (* Entries 3 and 4, for precise_first, then entries 5 and 6, for
     wide_first: two candidates with the same key, x = 1, one exit out = 7
     and the other out in [7..8]. They are supplied in opposite orders. *)
  let two name ~line ~first ~second =
    let x = formal name "x" in
    let call = stmt name `Call line and set = stmt name `Set (line + 1) in
    let reach =
      by_hand [ call; set; stmt name `Return (line + 2) ]
        ~zones:[ call, [x], []; set, [x], [out] ]
    in
    let entry v =
      ignore
        (Supplied.supply ~reach (kf name)
           ~key:(bases [x])
           ~input:(state [x, int 1])
           ~footprint:(footprint [x] [out])
           ~exit:(one_exit [x, int 1; out, v]))
    in
    entry first;
    entry second
  in
  two "precise_first" ~line:72 ~first:(int 7) ~second:(range 7 8);
  two "wide_first" ~line:77 ~first:(range 7 8) ~second:(int 7);
  (* Entry 7, for loop_on_4: key {x, g} with x = 1 and g in {3; 4}. The body
     returns only when g is 3: the exit state has g = 3, reduced, and
     out = 4. g is read, not written. Both branches of the condition are
     taken. *)
  let x = formal "loop_on_4" "x" in
  let s = stmt "loop_on_4" in
  let call = s `Call 88 and cond = s `If 89 and set = s `Set 90 in
  let reach =
    by_hand [ call; cond; s `Loop 89; set; s `Return 91 ]
      ~guards:[ cond, true; cond, false ]
      ~zones:[ call, [x; g], []; cond, [g], []; set, [x; g], [out] ]
  in
  ignore
    (Supplied.supply ~reach (kf "loop_on_4")
       ~key:(bases [x; g])
       ~input:(state [x, int 1; g, range 3 4])
       ~footprint:(footprint [x; g] [out])
       ~exit:(one_exit [x, int 1; g, int 3; out, int 4]));
  (* Entry 8, for write_then_spin: key {choice}. b is written only on the
     path that loops forever: it is in W, not in W_exit, and not in the key.
     The exit state holds the value 0 of b in the input of the producer. *)
  let s = stmt "write_then_spin" in
  let call = s `Call 96 and cond = s `If 97 and set_b = s `Set 98
  and set_out = s `Set 101 in
  let reach =
    by_hand [ call; cond; set_b; s `Loop 99; set_out; s `Return 102 ]
      ~guards:[ cond, true; cond, false ]
      ~zones:[ call, [], []; cond, [choice], []; set_b, [], [b];
               set_out, [], [out] ]
  in
  ignore
    (Supplied.supply ~reach (kf "write_then_spin")
       ~key:(bases [choice])
       ~input:(state [choice, Cvalue.V.top_int; b, int 0])
       ~footprint:(footprint [choice] [b; out] ~written_exit:[out])
       ~exit:(one_exit [choice, Cvalue.V.top_int; b, int 0; out, int 5]));
  (* Entry 9, for never_returns: no exit state. The return statement is
     not reached. *)
  let call = stmt "never_returns" `Call 105 in
  let reach =
    by_hand [ call; stmt "never_returns" `Loop 106 ] ~zones:[ call, [], [] ]
  in
  ignore
    (Supplied.supply ~reach (kf "never_returns")
       ~key:Base.Hptset.empty
       ~input:Cvalue.Model.empty_map
       ~footprint:(footprint [] [])
       ~exit:[]);
  (* Entry 10, for twice: key {x} with x = 3; returns 6. The block of the
     returned value is added to the written sets by the entry. *)
  let x = formal "twice" "x" in
  let result = Option.get (Supplied.return_variable (kf "twice")) in
  let retres =
    List.find (fun vi -> vi.vname = "__retres")
      (Kernel_function.get_definition (kf "twice")).slocals
  in
  let set = stmt "twice" `Set 110 and return = stmt "twice" `Return 110 in
  let reach =
    by_hand [ set; return ]
      ~zones:[ set, [x], [retres]; return, [retres], [result] ]
  in
  ignore
    (Supplied.supply ~reach (kf "twice")
       ~key:(bases [x])
       ~input:(state [x, int 3])
       ~footprint:(footprint [x] [])
       ~exit:(one_exit [x, int 3; result, int 6]));
  (* Entry 11, for leak_address: key {x} with x = 1; stores the address of
     the formal x in p. *)
  let x = formal "leak_address" "x" in
  let call = stmt "leak_address" `Call 114
  and set = stmt "leak_address" `Set 115 in
  let reach =
    by_hand [ call; set; stmt "leak_address" `Return 116 ]
      ~zones:[ call, [x], []; set, [], [p] ]
  in
  ignore
    (Supplied.supply ~reach (kf "leak_address")
       ~key:(bases [x])
       ~input:(state [x, int 1])
       ~footprint:(footprint [x] [p])
       ~exit:(one_exit [x, int 1; p, address_of x]));
  (* Entries refused by [supply]; no entry is added. *)
  let refused ?(key = Base.Hptset.empty) ?(input = Cvalue.Model.empty_map)
      ?(footprint = footprint [] [out]) exit =
    match Supplied.supply (kf "set_out") ~key ~input ~footprint ~exit with
    | _ -> Kernel.result "entry supplied, not refused"
    | exception Invalid_argument msg -> Kernel.result "refused: %s" msg
  in
  (* An exit state that does not bind the written block out. *)
  refused (one_exit [keep, int 0]);
  (* An input that is Top. *)
  refused ~input:Cvalue.Model.top (one_exit [out, int 7]);
  (* An exit state that is Top, then one that is Bottom. *)
  refused [ Supplied.empty_key, Cvalue.Model.top ];
  refused [ Supplied.empty_key, Cvalue.Model.bottom ];
  (* A key that does not contain the read block keep. *)
  refused ~footprint:(footprint [keep] [out]) (one_exit [out, int 7]);
  (* A key that does not contain out, written before an exit but not surely
     overwritten. *)
  refused ~footprint:(footprint [] [out] ~written_sure:[])
    (one_exit [out, int 7]);
  (* Written sets that are not nested: out is in W_exit and not in W. *)
  refused ~footprint:(footprint [] [] ~written_exit:[out])
    (one_exit [out, int 7])

let functions =
  [ "step"; "set_out"; "precise_first"; "wide_first"; "plain"; "loop_on_4";
    "write_then_spin"; "never_returns"; "twice"; "leak_address" ]

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
      Eva.Statistics.memexec_stored, "memexec-stored";
      Eva.Statistics.collector_would_store, "collector-would-store" ]
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
  List.iter print_entries functions;
  check_frame ();
  List.iter print_counts functions

let () = Boot.Main.extend run
