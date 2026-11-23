(* Device of the tests of the hits under a renaming (#125).

   In the analysis with -eva-hit-log, it records the cache entry of each
   call analysed by its body. After the analyses, it prints for each of
   these entries its members whose body did not run, its hits and the calls
   below a hit that use it: their callstack, and the renaming through which
   they use the entry, from the blocks of the analysed call of the entry to
   theirs.

   Then, for the function get, it takes the first two members of an entry
   on distinct callstacks, each with its renaming and its body-entry state.
   It applies the entry through the renaming of the first member to the
   body-entry state of the second, before the return statement of get,
   where the Inner part covers p and the block it points to, and compares
   the answer with the answer of the rule to each of the two
   members: the bases where they differ, each marked as covered by the
   Inner part of the entry renamed for the first member, or as of the
   frame.

   For the function same, it controls the guard of the rule on the members
   whose renaming has two pairs: the rule through this renaming gives a
   state, and the rule through a renaming that sends both blocks to the same
   block gives none. *)

type call = { kf: Kernel_function.t; id: int }

let calls = ref []
let project = ref None

let () =
  Eva.Cvalue_callbacks.register_call_results_hook
    (fun _callstack kf _body_entry results ->
       if Eva__Hit_log.enabled () then
         match results with
         | `Body (_, id) ->
           project := Some (Project.current ());
           calls := { kf; id } :: !calls
         | `Builtin _ | `Spec _ | `Reuse _ | `Renamed_reuse _ -> ())

(* One line, whatever its length. *)
let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  Buffer.contents buffer

let pp_list pp fmt = function
  | [] -> Format.pp_print_string fmt "none"
  | list ->
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> Format.pp_print_string fmt ", ") pp fmt list

let pp_renaming fmt = function
  | [] -> Format.pp_print_string fmt "identity"
  | pairs ->
    pp_list
      (fun fmt (b, image) ->
         Format.fprintf fmt "%a -> %a" Base.pretty b Base.pretty image)
      fmt pairs

let print_members call =
  let members = Eva__Hit_log.members ~id:call.id in
  if members <> [] then begin
    Format.printf "Members of the cache entry %d, %a, whose body did not run:@."
      call.id Kernel_function.pretty call.kf;
    List.iter
      (fun (callstack, renaming, _) ->
         Format.printf "  %s: %s@."
           (one_line Eva.Callstack.pretty callstack)
           (one_line pp_renaming renaming))
      members
  end

(* The bases bound in [m1] or in [m2] whose contents differ. *)
let differing_bases m1 m2 =
  match m1, m2 with
  | Cvalue.Model.Map map1, Cvalue.Model.Map map2 ->
    let bases map =
      Cvalue.Model.fold (fun base _ acc -> Base.Hptset.add base acc) map
        Base.Hptset.empty
    in
    let find base model =
      match Cvalue.Model.find_base base model with
      | `Value offsetmap -> Some offsetmap
      | `Top | `Bottom -> None
      | exception Not_found -> None
    in
    Base.Hptset.filter
      (fun base ->
         not (Option.equal Cvalue.V_Offsetmap.equal
                (find base m1) (find base m2)))
      (Base.Hptset.union (bases map1) (bases map2))
    |> Base.Hptset.elements
  | _ -> []

(* The entry of a call of get through the renaming of its first member,
   applied to the body-entry state of the second, before the return
   statement. *)
let control call =
  let members = Eva__Hit_log.members ~id:call.id in
  let first_two =
    match members with
    | (cs1, _, _) as first :: rest ->
      Option.map (fun second -> first, second)
        (List.find_opt
           (fun (cs, _, _) -> not (Eva.Callstack.equal cs cs1)) rest)
    | [] -> None
  in
  match first_two with
  | None -> ()
  | Some ((cs1, renaming1, entry1), (cs2, renaming2, entry2)) ->
    let stmt = Kernel_function.find_return call.kf in
    let point : Eva__Domain_store.control_point = Before stmt in
    Format.printf
      "Entry %d of %a through the renaming of %s, applied to the body-entry \
       state of %s, before the return statement:@."
      call.id Kernel_function.pretty call.kf
      (one_line Eva.Callstack.pretty cs1) (one_line Eva.Callstack.pretty cs2);
    let rule renaming body_entry =
      Eva__Hit_log.rule ~id:call.id ~renaming ~body_entry point
    in
    let covered =
      match Eva__Hit_log.point_view ~id:call.id point with
      | Inner { covered; _ } ->
        let image b =
          match List.find_opt (fun (b', _) -> Base.equal b b') renaming1 with
          | Some (_, image) -> image
          | None -> b
        in
        Base.Hptset.fold
          (fun b acc -> Base.Hptset.add (image b) acc) covered
          Base.Hptset.empty
      | Full_states | No_point -> Base.Hptset.empty
    in
    let pp_base fmt base =
      Format.fprintf fmt "%a (%s)" Base.pretty base
        (if Base.Hptset.mem base covered then "covered" else "frame")
    in
    match rule renaming1 entry2, rule renaming1 entry1, rule renaming2 entry2
    with
    | Some applied, Some first, Some second ->
      Format.printf "  differs from the answer to the first member on: %s@."
        (one_line (pp_list pp_base) (differing_bases applied first));
      Format.printf "  differs from the answer to the second member on: %s@."
        (one_line (pp_list pp_base) (differing_bases applied second))
    | _ -> Format.printf "  no answer from the rule@."

(* The guard of the rule on the members of an entry of same whose renaming
   has two pairs, before the return statement. *)
let guard call =
  let point : Eva__Domain_store.control_point =
    Before (Kernel_function.find_return call.kf)
  in
  List.iter
    (function
      | callstack, [ a, x; b, y ], body_entry ->
        let answer renaming =
          match Eva__Hit_log.rule ~id:call.id ~renaming ~body_entry point with
          | Some _ -> "a state"
          | None -> "no state"
        in
        Format.printf
          "Guard of the rule on the entry %d of %a, for %s, before the return \
           statement:@."
          call.id Kernel_function.pretty call.kf
          (one_line Eva.Callstack.pretty callstack);
        List.iter
          (fun renaming ->
             Format.printf "  through %s: %s@."
               (one_line pp_renaming renaming) (answer renaming))
          [ [ a, x; b, y ]; [ a, x; b, x ] ]
      | _ -> ())
    (Eva__Hit_log.members ~id:call.id)

let main () =
  match !project with
  | None -> ()
  | Some project ->
    Project.on project
      (fun () ->
         let calls = List.rev !calls in
         List.iter print_members calls;
         List.iter
           (fun call ->
              match Kernel_function.get_name call.kf with
              | "get" -> control call
              | "same" -> guard call
              | _ -> ())
           calls)
      ()

let () = Boot.Main.extend main
