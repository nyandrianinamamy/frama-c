(* Device of the tests of the heap effects that a hit passes to the call
   that makes it (#128).

   In the analysis with -eva-hit-log, it records each call of a function
   defined in the test whose name does not end with _main, with the outputs
   that the inout plugin gives for it: the over-approximated outputs, those
   on the paths that return, and the sure outputs. For such a call analysed by its body, it also records the
   heap effects that the call received, in the order of their emission,
   and, if memexec stores it, its key and the blocks it creates, as memexec
   gives them to its store hooks.

   After the analyses, it prints these calls in the order of their ends.
   For each of them analysed by its body, it also prints, before each
   labelled statement of its function, what its cache entry holds there:
   the allocated blocks that its Inner part covers, those of them that it
   does not bind, and the blocks swept on every path and on some path
   only.

   An allocated block that the policy by_stack made is named by its stack
   and its rank on that stack, never by its name, so that two runs whose
   callstacks are the same print the same lines; the suffix of the stack of
   an allocation below the callstack of the call is printed too. *)

type call = {
  callstack: Eva.Callstack.t;
  kind: string;
  id: int option;
  outputs: (Memory_zone.t * Memory_zone.t * Memory_zone.t) option;
  mutable effects: Eva__Hit_log.effects option;
  mutable stored: (Base.Hptset.t * Base.t list) option;
}

let calls = ref []
let project = ref None

let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  String.map (fun c -> if c = '\n' then ' ' else c) (Buffer.contents buffer)

let observed kf =
  Kernel_function.is_definition kf
  && not (String.ends_with ~suffix:"_main" (Kernel_function.get_name kf))

(* The outputs of the last call whose results the inout plugin recorded:
   its hook runs before the call-results hook of this device. *)
let last_inout = ref None

let () =
  Eva__Eva_dynamic.Inout.register_call_hook
    (fun inout ->
       if Eva__Hit_log.enabled () then
         last_inout :=
           Some (inout.Inout_type.over_outputs,
                 inout.Inout_type.over_outputs_if_termination,
                 inout.Inout_type.under_outputs_if_termination))

let () =
  Eva.Cvalue_callbacks.register_call_results_hook
    (fun callstack kf _state results ->
       if Eva__Hit_log.enabled () then begin
         let outputs = !last_inout in
         last_inout := None;
         if observed kf then begin
           project := Some (Project.current ());
           let kind, id =
             match results with
             | `Body (_, id) -> "analysed", Some id
             | `Reuse _ | `Renamed_reuse _ | `Swept_reuse _ -> "hit", None
             | `Builtin _ -> "builtin", None
             | `Spec _ -> "specification", None
           in
           calls :=
             { callstack; kind; id; outputs; effects = None; stored = None }
             :: !calls
         end
       end)

let () =
  Eva__Mem_exec.register_store_hook
    (fun kf id (entry: Eva__Numbering.entry) ->
       if observed kf then
         List.iter
           (fun call ->
              if call.id = Some id then
                call.stored <- Some (entry.key, entry.created))
           !calls)

let () =
  Eva__Hit_log.register_effects_hook
    (fun callstack effects ->
       if observed (Eva.Callstack.top_kf callstack) then
         match
           List.find_opt
             (fun call ->
                call.effects = None && Eva.Callstack.equal call.callstack callstack)
             !calls
         with
         | Some call -> call.effects <- Some effects
         | None -> ())

(* ----- Names of the blocks ---------------------------------------------- *)

let pp_callstack fmt cs = Format.pp_print_string fmt (one_line Eva.Callstack.pretty cs)

(* The name of each block that the policy by_stack made, by its stack and
   rank, in the current project. *)
let names () =
  let names = Base.Hashtbl.create 17 in
  Eva__Builtins_malloc.fold_malloced_by_stack
    (fun stack bases () ->
       List.iteri
         (fun rank base ->
            Base.Hashtbl.replace names base
              (Format.asprintf "block %d of %a" rank pp_callstack stack))
         bases)
    ();
  names

let name names base =
  match Base.Hashtbl.find_opt names base with
  | Some name -> name
  | None -> one_line Base.pretty base

let pp_bases names fmt set =
  let list = List.sort compare (List.map (name names) set) in
  match list with
  | [] -> Format.pp_print_string fmt "none"
  | _ -> Format.pp_print_string fmt (String.concat ", " list)

let pp_set names fmt set = pp_bases names fmt (Base.Hptset.elements set)

let pp_zone names fmt zone =
  match zone with
  | Memory_zone.Top _ -> Format.pp_print_string fmt "top"
  | Memory_zone.Map _ ->
    let cells =
      Memory_zone.fold_i
        (fun base itv acc ->
           (name names base ^ one_line Int_Intervals.pretty itv) :: acc)
        zone []
    in
    match List.sort compare cells with
    | [] -> Format.pp_print_string fmt "none"
    | cells -> Format.pp_print_string fmt (String.concat "; " cells)

(* ----- Heap effects ----------------------------------------------------- *)

let rec drop n list = if n <= 0 then list else drop (n - 1) (List.tl list)
let rec take n list =
  if n <= 0 then [] else List.hd list :: take (n - 1) (List.tl list)

let pretty_suffix ~(call: Eva.Callstack.t) fmt (stack: Eva.Callstack.t) =
  let below = List.length stack.stack - List.length call.stack in
  if below > 0
  && Eva.Callstack.equal { stack with stack = drop below stack.stack } call
  then
    Format.fprintf fmt "suffix %a"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.pp_print_string fmt " <- ")
         (fun fmt (kf, stmt) ->
            Format.fprintf fmt "%a :: %a" Kernel_function.pretty kf
              Fileloc.pretty (Cil_datatype.Stmt.loc stmt)))
      (take below stack.stack)
  else Format.pp_print_string fmt "stack not below the call"

let pp_effect names ~call fmt (e: Eva__Heap_effects.t) =
  let name = name names in
  match e with
  | Allocation { block; stack; rank; decision; _ } ->
    Format.fprintf fmt "allocation of %s, %a, rank %s, %a" (name block)
      (pretty_suffix ~call) stack
      (match rank with None -> "none" | Some r -> string_of_int r)
      (fun fmt -> function
         | Eva__Heap_effects.Created -> Format.pp_print_string fmt "created"
         | Reused { weakened } ->
           Format.fprintf fmt "reused%s" (if weakened then ", weakened" else ""))
      decision
  | Mutation { block; record; weakened; typ } ->
    Format.fprintf fmt "validity mutation of %s%s%s%s" (name block)
      (if Option.is_some record then ", record" else "")
      (if weakened then ", weakened" else "")
      (if Option.is_some typ then ", type" else "")
  | Removal block -> Format.fprintf fmt "removal of %s" (name block)
  | Sweep { block; exact } ->
    Format.fprintf fmt "sweep of %s, %s" (name block)
      (if exact then "exact" else "joined")

let print_effects names call effects =
  Format.printf "  heap effects:@.";
  let none = ref true in
  Eva__Hit_log.iter_effects
    (fun point callee e ->
       none := false;
       Format.printf "    %s%s: %s@."
         (match point with
          | None -> "no statement"
          | Some stmt ->
            one_line Fileloc.pretty (Cil_datatype.Stmt.loc stmt))
         (match callee with
          | None -> ""
          | Some kf -> ", in " ^ Kernel_function.get_name kf)
         (one_line (pp_effect names ~call:call.callstack) e))
    effects;
  if !none then Format.printf "    none@."

(* ----- Points of the entry ---------------------------------------------- *)

let is_allocated = function Base.Allocated _ -> true | _ -> false

let bound inner =
  match inner with
  | Cvalue.Model.Map map -> Base.Hptset.from_map (Cvalue.Model.shape map)
  | Top | Bottom -> Base.Hptset.empty

let labelled kf =
  match kf.Cil_types.fundec with
  | Declaration _ -> []
  | Definition (fundec, _) ->
    List.filter_map
      (fun stmt ->
         List.find_map
           (function
             | Cil_types.Label (name, _, true) -> Some (name, stmt)
             | Label _ | Case _ | Default _ -> None)
           stmt.Cil_types.labels)
      fundec.sallstmts

let print_points names call id =
  List.iter
    (fun (label, stmt) ->
       let text =
         match Eva__Hit_log.point_view ~id (Before stmt) with
         | Full_states -> "full states"
         | No_point -> "no Inner part"
         | Inner { covered; inner; swept_every; swept_some } ->
           let covered = Base.Hptset.filter is_allocated covered in
           let unbound = Base.Hptset.diff covered (bound inner) in
           Format.asprintf
             "covers %a; does not bind %a; swept on every path: %a; on \
              some path only: %a"
             (pp_set names) covered (pp_set names) unbound
             (pp_set names) swept_every (pp_set names) swept_some
       in
       Format.printf "  before %s: %s@." label text)
    (labelled (Eva.Callstack.top_kf call.callstack))

(* ----- Printing ----------------------------------------------------------- *)

let print names call =
  Format.printf "%a, %s:@." pp_callstack call.callstack call.kind;
  begin match call.outputs with
    | None -> Format.printf "  no outputs from the inout plugin@."
    | Some (outputs, returning, sure) ->
      Format.printf
        "  outputs: %a@.  outputs on return: %a@.  sure outputs: %a@."
        (pp_zone names) outputs (pp_zone names) returning (pp_zone names) sure
  end;
  match call.id with
  | Some id ->
    Option.iter (print_effects names call) call.effects;
    begin match call.stored with
      | None -> Format.printf "  not stored by memexec@."
      | Some (key, created) ->
        Format.printf "  stored by memexec, key: %a@.  created: %a@."
          (pp_set names) key (pp_bases names) created
    end;
    print_points names call id
  | None -> ()

let main () =
  match !project with
  | None -> ()
  | Some project ->
    Project.on project
      (fun () ->
         let names = names () in
         Format.printf "Calls of the functions of the test:@.";
         List.iter (print names) (List.rev !calls))
      ()

let () = Boot.Main.extend main
