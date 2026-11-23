(* Device of the test of the snapshot at the start of a call (#126).

   In the analysis with -eva-hit-log, at the start of each call of a
   function analysed by its body, it takes the snapshot of each allocated
   block of the start state, as it is then. When the call ends, it rebuilds
   the snapshot of these blocks at the start of the call from the blocks as
   they are at the end and from the validity mutations that the call
   received, in the order of their emission, as memexec does when it stores
   a call. For each call with at least one allocated block at its start, it
   prints the number of these blocks, the number of mutations received, the
   blocks whose rebuilt snapshot differs from the one taken at the start,
   and, as a control, the blocks whose snapshot at the end differs from the
   one taken at the start. *)

let is_allocated = function
  | Base.Allocated _ -> true
  | Base.Var _ | Base.CLogic_Var _ | Base.Null | Base.Absolute _ -> false

let allocated_blocks (state: Cvalue.Model.t) =
  match state with
  | Bottom | Top -> []
  | Map map ->
    Cvalue.Model.fold
      (fun base _ acc -> if is_allocated base then base :: acc else acc)
      map []
    |> List.rev

(* The snapshots taken at the start of the calls not ended yet, per
   callstack, the innermost first. *)
let starts = Eva.Callstack.Hashtbl.create 17

let () =
  Eva.Cvalue_callbacks.register_call_hook
    (fun callstack _kf state kind ->
       match kind with
       | `Body ->
         let blocks =
           List.map
             (fun base -> base, Eva__Mem_exec.take_block base)
             (allocated_blocks state)
         in
         let previous =
           Option.value ~default:[]
             (Eva.Callstack.Hashtbl.find_opt starts callstack)
         in
         Eva.Callstack.Hashtbl.replace starts callstack (blocks :: previous)
       | `Builtin | `Spec | `Reuse -> ())

(* One line, whatever its length. *)
let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  Buffer.contents buffer

let equal_option a b =
  match a, b with
  | None, None -> true
  | Some a, Some b -> Eva__Mem_exec.equal_block a b
  | None, Some _ | Some _, None -> false

let pp_differs fmt = function
  | [] -> Format.pp_print_string fmt "none"
  | bases ->
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> Format.pp_print_string fmt ", ")
      Base.pretty fmt bases

let check callstack effects =
  match Eva.Callstack.Hashtbl.find_opt starts callstack with
  | None | Some [] -> ()
  | Some (blocks :: previous) ->
    Eva.Callstack.Hashtbl.replace starts callstack previous;
    if blocks <> [] then begin
      let mutations = ref [] in
      Eva__Hit_log.iter_effects
        (fun _ _ e ->
           match e with
           | Eva__Heap_effects.Mutation _ -> mutations := e :: !mutations
           | Allocation _ | Removal _ | Sweep _ -> ())
        effects;
      let mutations = List.rev !mutations in
      let differs take =
        List.filter_map
          (fun (base, start) ->
             if equal_option (take base) start then None else Some base)
          blocks
      in
      let rebuilt = differs (Eva__Mem_exec.take_block_at_entry ~mutations) in
      let at_end = differs Eva__Mem_exec.take_block in
      Format.printf "%s: %d blocks at the start, %d mutations; rebuilt \
                     snapshot differs on: %a; snapshot at the end differs \
                     on: %a.@."
        (one_line Eva.Callstack.pretty callstack)
        (List.length blocks) (List.length mutations)
        pp_differs rebuilt pp_differs at_end
    end

let () = Eva__Hit_log.register_effects_hook check
