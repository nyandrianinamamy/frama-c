(* Device of the tests of the rule on the heap calls (#122).

   In the analysis with -eva-hit-log, it records each call analysed by its
   body, with its body-entry state and its cache entry. After the analyses,
   it prints for each of these calls, before each labelled statement of its
   function, what the cache entry holds there: full states, or the allocated
   blocks that the Inner part covers, those of them that it does not bind
   (the removal mask), and the blocks swept on every path from the start of
   the body and on some path only.

   Then, for each function named release or crelease, with two calls on the
   same callstack whose body-entry states differ in spare only, it applies
   the cache entry of the call in which spare does not point to an
   allocated block to the body-entry state of the other call, before the
   labelled statement of the function, and compares the answer with the
   answer of the entry of the other call, as the rule gives them. *)

type call = {
  kf: Kernel_function.t;
  callstack: Eva.Callstack.t;
  body_entry: Cvalue.Model.t;
  id: int;
}

let calls = ref []
let project = ref None

let () =
  Eva.Cvalue_callbacks.register_call_results_hook
    (fun callstack kf body_entry results ->
       if Eva__Hit_log.enabled () then
         match results with
         | `Body (_, id) ->
           project := Some (Project.current ());
           calls := { kf; callstack; body_entry; id } :: !calls
         | `Builtin _ | `Spec _ | `Reuse _ | `Renamed_reuse _
         | `Swept_reuse _ -> ())

(* One line, whatever its length. *)
let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  Buffer.contents buffer

let is_allocated = function
  | Base.Allocated _ -> true
  | _ -> false

let pp_blocks fmt set =
  if Base.Hptset.is_empty set then Format.pp_print_string fmt "none"
  else
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> Format.pp_print_string fmt ", ")
      Base.pretty fmt (Base.Hptset.elements set)

(* The blocks of [inner]. *)
let bound inner =
  match inner with
  | Cvalue.Model.Map map ->
    Base.Hptset.from_map (Cvalue.Model.shape map)
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

let print_points call =
  Format.printf "%s, cache entry %d:@."
    (one_line Eva.Callstack.pretty call.callstack) call.id;
  List.iter
    (fun (label, stmt) ->
       let view = Eva__Hit_log.point_view ~id:call.id (Before stmt) in
       let text =
         match view with
         | Full_states -> "full states"
         | No_point -> "no Inner part"
         | Inner { covered; inner; swept_every; swept_some } ->
           let covered = Base.Hptset.filter is_allocated covered in
           let unbound = Base.Hptset.diff covered (bound inner) in
           Format.asprintf
             "covers %a; does not bind %a; swept on every path: %a; \
              on some path only: %a"
             pp_blocks covered pp_blocks unbound
             pp_blocks swept_every pp_blocks swept_some
       in
       Format.printf "  before %s: %s@." label text)
    (labelled call.kf)

(* The value of spare in [state], if it is bound there: the join of the
   values of its offsetmap. *)
let spare state =
  let vi = Globals.Vars.find_from_astinfo "spare" Global in
  let base = Base.of_varinfo vi in
  match Cvalue.Model.find_base base state with
  | `Value offsetmap ->
    let value =
      Cvalue.V_Offsetmap.fold_on_values Cvalue.V_Or_Uninitialized.join
        offsetmap Cvalue.V_Or_Uninitialized.bottom
    in
    one_line Cvalue.V_Or_Uninitialized.pretty value
  | `Top -> "top"
  | `Bottom -> "bottom"
  | exception Not_found -> "absent"

let points_to_block call =
  match Cvalue.Model.find_base
          (Base.of_varinfo (Globals.Vars.find_from_astinfo "spare" Global))
          call.body_entry
  with
  | `Value offsetmap ->
    Cvalue.V_Offsetmap.fold_on_values
      (fun v acc ->
         acc ||
         Cvalue.V.fold_bases
           (fun b acc -> acc || is_allocated b)
           (Cvalue.V_Or_Uninitialized.get_v v) false)
      offsetmap false
  | `Top | `Bottom -> false
  | exception Not_found -> false

(* Applies the entry of [first], whose spare does not point to an allocated
   block, to the body-entry state of [other], before [label]. *)
let apply name ~first ~other (label, stmt) =
  Format.printf
    "Entry %d of %s, without pointer in spare, applied to the body-entry \
     state of the call of entry %d, before %s:@."
    first.id name other.id label;
  let rule call =
    Eva__Hit_log.rule ~id:call.id ~body_entry:other.body_entry (Before stmt)
  in
  match rule first, rule other with
  | Some pasted, Some own ->
    Format.printf "  spare: %s@.  with entry %d: %s@.  equal: %b@."
      (spare pasted) other.id (spare own) (Cvalue.Model.equal pasted own)
  | None, _ | _, None ->
    Format.printf "  no answer from the rule: full states@."

let control name =
  let of_kf =
    List.filter
      (fun call -> Kernel_function.get_name call.kf = name)
      (List.rev !calls)
  in
  match of_kf with
  | [] -> ()
  | call :: _ ->
    match List.partition points_to_block of_kf, labelled call.kf with
    | ([ other ], [ first ]), [ point ] -> apply name ~first ~other point
    | _ -> ()

let main () =
  match !project with
  | None -> ()
  | Some project ->
    Project.on project
      (fun () ->
         Format.printf "Points of the cache entries:@.";
         List.iter print_points (List.rev !calls);
         List.iter control [ "release"; "crelease" ])
      ()

let () = Boot.Main.extend main
