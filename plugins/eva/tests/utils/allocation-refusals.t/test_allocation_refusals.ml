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

(* The paths of the kernel that do not go through the allocation builtins. *)
let allocated ~weak name =
  let size = Z.of_int 31 in
  let validity =
    Base.create_variable_validity ~weak ~min_alloc:size ~max_alloc:size
  in
  let vi = Cil.makeGlobalVar ~source:false name Cil_const.intType in
  Base.register_allocated_var vi Base.Malloc (Base.Variable validity),
  validity

let weaken validity =
  let size = Z.of_int 31 in
  Base.update_variable_validity validity ~weak:true
    ~min_alloc:size ~max_alloc:size

let capture f =
  let stack =
    let entry_point = Globals.Functions.find_by_name "main" in
    Eva.Callstack.init ~thread:0 ~entry_point
  in
  match Eva__Body_access.capture stack f with
  | (), Some r -> r
  | (), None -> failwith "no observation"

let tags () =
  let r = capture Eva__Body_access.read_node_tags in
  Format.printf "tags: %s%s@." (first_reason r)
    (if owners r = [] then ", no owner" else "")

(* An observer set before a recording runs before, during and after it. *)
let observer_before () =
  let observed, _ = allocated ~weak:false "observed" in
  let calls = ref 0 in
  let read () = ignore (Base.validity observed) in
  let previous = Base.observe_metadata_reads (Some (fun _ -> incr calls)) in
  read ();
  assert (!calls = 1);
  let r = capture read in
  assert (!calls = 2);
  read ();
  assert (!calls = 3);
  ignore (Base.observe_metadata_reads previous);
  Format.printf "observer set before: runs %d, collector owners: %s@."
    !calls (String.concat " " (owners r))

(* An observer set during a recording, which forwards to the one it
   replaced, is kept when the recording ends; the collector records the
   reads of a later recording, once each, and is gone when the client
   restores what it replaced. *)
let observer_during () =
  let observed, _ = allocated ~weak:false "late" in
  let calls = ref 0 in
  let read () = ignore (Base.validity observed) in
  let displaced = ref None in
  let late =
    Some (fun base -> incr calls; Option.iter (fun f -> f base) !displaced)
  in
  let first =
    capture (fun () -> displaced := Base.observe_metadata_reads late; read ())
  in
  assert (!calls = 1);
  read ();
  assert (!calls = 2);
  let second = capture read in
  assert (!calls = 3);
  let top = Base.observe_metadata_reads None in
  ignore (Base.observe_metadata_reads top);
  let kept = top == late in
  ignore (Base.observe_metadata_reads !displaced);
  ignore (capture (fun () -> ()));
  let idle = Base.observe_metadata_reads None in
  Format.printf
    "observer set during: runs %d, kept %b, owners: %s; %s, idle after: %b@."
    !calls kept (String.concat " " (owners first))
    (String.concat " " (owners second)) (idle = None);
  Format.printf "observer set during: %s; %s@."
    (first_reason first) (first_reason second)

(* An observer set during a recording that does not forward hides the read:
   the recording is refused without owner, also when the client restores
   the observer it replaced before the recording ends. *)
let observer_hiding () =
  let observed, _ = allocated ~weak:false "hidden" in
  let read () = ignore (Base.validity observed) in
  let hide ~restore () =
    let displaced = Base.observe_metadata_reads (Some ignore) in
    read ();
    if restore then ignore (Base.observe_metadata_reads displaced)
  in
  let kept = capture (hide ~restore:false) in
  ignore (Base.observe_metadata_reads None);
  let restored = capture (hide ~restore:true) in
  let quiet = capture (fun () -> ()) in
  Format.printf "observer hiding: %s%s; %s%s; then %s@."
    (first_reason kept) (if owners kept = [] then ", no owner" else "")
    (first_reason restored) (if owners restored = [] then ", no owner" else "")
    (first_reason quiet)

(* An observer of updates that reads metadata: the read reaches the
   collector and the observer of reads. *)
let observer_nested () =
  let observed, validity = allocated ~weak:true "nested" in
  let reads = ref 0 in
  let previous_read = Base.observe_metadata_reads (Some (fun _ -> incr reads)) in
  let previous_update =
    Base.observe_validity_updates
      (Some (fun _ ~weak:_ -> ignore (Base.validity observed)))
  in
  let r = capture (fun () -> weaken validity) in
  ignore (Base.observe_validity_updates previous_update);
  ignore (Base.observe_metadata_reads previous_read);
  Format.printf "observer nested: %s, owners: %s, reads seen: %d@."
    (String.concat " " (reasons r)) (String.concat " " (owners r)) !reads

(* A validity record made weak through the kernel alone refuses the bodies
   that consult the node tags, and so does a second registration of a
   variable. *)
let kernel_paths () =
  observer_before ();
  observer_during ();
  observer_hiding ();
  observer_nested ();
  tags ();
  let base, _ = allocated ~weak:false "registered" in
  let validity =
    Base.create_variable_validity ~weak:true ~min_alloc:Z.zero ~max_alloc:Z.one
  in
  ignore (Base.register_allocated_var (Base.to_varinfo base) Base.Malloc
            (Base.Variable validity));
  tags ()

module Saved =
  State_builder.Option_ref
    (Cvalue.V_Offsetmap)
    (struct
      let name = "Test_allocation_refusals.Saved"
      let dependencies = [ Ast.self ]
    end)

(* A node built while its target is strong keeps its tag in a saved session:
   the weakening is saved with it. *)
let kernel_save () =
  let base, validity = allocated ~weak:false "saved" in
  let value =
    Cvalue.V_Or_Uninitialized.initialized (Cvalue.V.inject base Ival.zero)
  in
  let size = Z.of_int 64 in
  Saved.set (Cvalue.V_Offsetmap.create ~size value ~size_v:size);
  tags ();
  weaken validity;
  tags ();
  (* The count of the process remains when the state alone is cleared. *)
  let state = State.get "Base.Weakenings" in
  Project.clear ~selection:(State_selection.singleton state) ();
  tags ();
  (* The saved session holds a count again. *)
  weaken (snd (allocated ~weak:false "again"))

let kernel_load () =
  let map = Saved.get () in
  Format.printf "loaded node tag: %b@."
    (Cvalue.V_Offsetmap.cardinal_zero_or_one map);
  tags ()

let () =
  match Sys.getenv_opt "EVA_TEST_ALLOCATION" with
  | Some "kernel" -> Boot.Main.extend kernel_paths
  | Some "kernel-save" -> Boot.Main.extend kernel_save
  | Some "kernel-load" -> Boot.Main.extend kernel_load
  | _ -> ()

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
    | Some ("kernel" | "kernel-save" | "kernel-load") -> ()
    | _ -> failwith "EVA_TEST_ALLOCATION is not set"
  in
  Access.on_result observe
