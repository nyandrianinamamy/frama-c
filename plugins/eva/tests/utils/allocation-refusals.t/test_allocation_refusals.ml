module Access = Eva.Body_access

let reasons (r : Access.t) = List.map Access.refusal_id r.refusals

let first_reason (r : Access.t) =
  match r.refusals with
  | [] -> "would-store"
  | reason :: _ -> Access.refusal_id reason

let refused_for reason (r : Access.t) = List.mem reason r.refusals

let is_allocated = function Base.Allocated _ -> true | _ -> false

let names = function
  | Base.SetLattice.Top -> failwith "unexpected Top"
  | Base.SetLattice.Set bases ->
    let add b names = (Base.to_varinfo b).vname :: names in
    List.sort String.compare (Base.Hptset.fold add bases [])

let owners (r : Access.t) = names (Base.SetLattice.inject r.owners)

let effects = Access.[ Reallocation; Allocation; Deallocation ]

let performs_no_effect (r : Access.t) =
  not (List.exists (fun e -> refused_for e r) effects)
  && not (refused_for Validity_mutation r)

let print name (r : Access.t) = Format.printf "%s %s@." name (first_reason r)

(* Bodies that read an allocated block, and bodies that perform an
   allocation effect. *)
let scratch_once_calls = ref 0

let observe_effects name (r : Access.t) =
  match name with
  | "copy" ->
    assert (names r.reads = ["p"]);
    assert (names r.writes = ["q"]);
    assert (Base.SetLattice.exists is_allocated r.designated);
    assert (performs_no_effect r);
    print name r
  | "logic_only" ->
    assert (names r.reads = ["p"]);
    assert (names r.writes = ["x"]);
    assert (Base.SetLattice.exists is_allocated r.designated);
    assert (performs_no_effect r);
    Format.printf "logic_only: %s@." (String.concat " " (reasons r))
  | "allocate" | "release" | "vla" -> print name r
  | "resize" ->
    assert (refused_for Allocation r && refused_for Deallocation r);
    print name r
  | "scratch" ->
    assert (refused_for Deallocation r);
    print name r
  | "scratch_once" ->
    incr scratch_once_calls;
    if !scratch_once_calls = 2 then begin
      assert (r.refusals = [Deallocation]);
      assert (owners r = []);
    end;
    Format.printf "scratch_once call %d %s@." !scratch_once_calls
      (first_reason r)
  | "main" ->
    assert (List.for_all (fun e -> refused_for e r) effects);
    assert (owners r <> []);
    print name r
  | name -> failwith ("unexpected body: " ^ name)

(* Loops whose widening reads or updates the validity of an allocated
   block. *)
let shift_calls = ref 0

let observe_widening name (r : Access.t) =
  let untouched () =
    assert (not (Base.SetLattice.exists is_allocated r.reads));
    assert (not (Base.SetLattice.exists is_allocated r.writes));
    assert (not (Base.SetLattice.exists is_allocated r.designated));
    assert (performs_no_effect r)
  in
  match name with
  | "shift" ->
    incr shift_calls;
    untouched ();
    if !shift_calls = 1 then begin
      assert (not (refused_for Allocation_metadata r));
      assert (owners r = []);
      Format.printf "shift before the allocation: no owner@."
    end else begin
      assert (refused_for Allocation_metadata r);
      Format.printf "shift after the allocation: owners %s@."
        (String.concat ", " (owners r))
    end
  | "quiet" ->
    untouched ();
    print name r
  | "fill" ->
    assert (refused_for Validity_mutation r);
    assert (not (List.exists (fun e -> refused_for e r) effects));
    print name r
  | "main" -> ()
  | name -> failwith ("unexpected body: " ^ name)

let observe_equality name (r : Access.t) =
  match name with
  | "equal_live" ->
    assert (refused_for Allocated_block r);
    assert (refused_for Allocation_metadata r);
    assert (owners r <> []);
    assert (names r.reads = ["__retres"; "a"; "b"]);
    print name r
  | "main" -> ()
  | name -> failwith ("unexpected body: " ^ name)

let observe_release name (r : Access.t) =
  match name with
  | "release" ->
    assert (refused_for Deallocation r);
    print name r
  | "main" ->
    assert (refused_for Allocation r && refused_for Deallocation r);
    print name r
  | name -> failwith ("unexpected body: " ^ name)

(* Bodies that do not access the block that their requires clauses read. *)
let observe_requires name (r : Access.t) =
  match name with
  | "valid_only" | "initialized_only" | "length_only" ->
    assert (names r.reads = []);
    assert (names r.writes = ["x"]);
    assert (not (Base.SetLattice.exists is_allocated r.designated));
    assert (refused_for Allocated_block r);
    assert (refused_for Allocation_metadata r);
    Format.printf "%s %s, owners %s@." name (first_reason r)
      (String.concat ", " (owners r))
  | "main" -> ()
  | name -> failwith ("unexpected body: " ^ name)

(* Prints all the reasons of the [n]th observation of a body, and its
   owners. *)
let calls = Hashtbl.create 17

let print_all name (r : Access.t) =
  let n = 1 + Option.value ~default:0 (Hashtbl.find_opt calls name) in
  Hashtbl.replace calls name n;
  let shown = if r.refusals = [] then "would-store"
    else String.concat " " (reasons r)
  in
  let owners =
    match owners r with
    | [] -> ""
    | owners -> ", owners " ^ String.concat " " owners
  in
  Format.printf "%s call %d: %s%s@." name n shown owners

(* Bodies whose requires clauses load or scan a block at the call site: the
   clauses add nothing to R. *)
let observe_call_site name (r : Access.t) =
  match name with
  | "c_word" ->
    assert (names r.reads = ["u"; "w"]);
    print_all name r
  | "req_word" | "req_initialized" | "req_plain" ->
    assert (names r.reads = []);
    assert (names r.writes = ["result"]);
    print_all name r
  | "scan" | "length" | "scan_unknown" | "initialized_unknown" ->
    assert (names r.reads = []);
    assert (names r.writes = ["x"]);
    print_all name r
  | "main" -> ()
  | name -> failwith ("unexpected body: " ^ name)

(* Bodies that neither read nor designate the allocated block. *)
let observe_unread name (r : Access.t) =
  match name with
  | "main" -> ()
  | "alloc" -> print_all name r
  | name ->
    assert (not (Base.SetLattice.exists is_allocated r.reads));
    assert (not (Base.SetLattice.exists is_allocated r.writes));
    assert (not (Base.SetLattice.exists is_allocated r.designated));
    print_all name r

let observe_all name (r : Access.t) = print_all name r

let () =
  Eva.Builtins.register_builtin "Frama_C_unknown_target"
    (fun _ _ -> Eva.Builtins.Result [Cvalue.V.top])

(* An observer of the kernel set before a recording keeps running during
   it and after it. A validity record made weak through the kernel, without
   the allocation builtins, refuses the bodies that consult the node tags. *)
let kernel_paths () =
  let allocated name =
    let size = Z.of_int 31 in
    let validity =
      Base.create_variable_validity ~weak:false ~min_alloc:size ~max_alloc:size
    in
    let vi = Cil.makeGlobalVar ~source:false name Cil_const.intType in
    Base.register_allocated_var vi Base.Malloc (Base.Variable validity),
    validity
  in
  let stack =
    let entry_point = Globals.Functions.find_by_name "main" in
    Eva.Callstack.init ~thread:0 ~entry_point
  in
  let capture f =
    match Eva__Body_access.capture stack f with
    | (), Some r -> r
    | (), None -> failwith "no observation"
  in
  let observed, _ = allocated "observed" in
  let calls = ref 0 in
  let read () = ignore (Base.validity observed) in
  let previous = Base.observe_metadata_reads (Some (fun _ -> incr calls)) in
  read ();
  let r = capture read in
  read ();
  ignore (Base.observe_metadata_reads previous);
  Format.printf "observer runs: %d, collector owners: %s@."
    !calls (String.concat " " (owners r));
  let tags () =
    let r = capture Eva__Body_access.read_node_tags in
    Format.printf "tags: %s@." (first_reason r)
  in
  tags ();
  let _, validity = allocated "weakened" in
  let size = Z.of_int 31 in
  Base.update_variable_validity validity ~weak:true
    ~min_alloc:size ~max_alloc:size;
  tags ()

let () =
  if Sys.getenv_opt "EVA_TEST_ALLOCATION" = Some "kernel" then
    Boot.Main.extend kernel_paths

let () =
  let observe stack result =
    let name = Kernel_function.get_name (Eva.Callstack.top_kf stack) in
    match Sys.getenv_opt "EVA_TEST_ALLOCATION" with
    | Some "effects" -> observe_effects name result
    | Some "widening" -> observe_widening name result
    | Some "equality" -> observe_equality name result
    | Some "release" -> observe_release name result
    | Some "requires" -> observe_requires name result
    | Some "call-site" -> observe_call_site name result
    | Some ("contents" | "weakening") -> observe_unread name result
    | Some ("finalisation" | "hit") -> observe_all name result
    | Some "kernel" -> ()
    | _ -> failwith "EVA_TEST_ALLOCATION is not set"
  in
  Access.on_result observe
