(* Device of the tests of the reuse of a call that allocates (#127).

   When an analysis of any project ends, it describes the two tables of the
   allocated blocks of the builtins of allocation: the list of the blocks
   that the policy by_stack made on each stack, and the callstack that owns
   each allocated block. A block is described by its strength, validity
   record, type and kind, never by its name: block names differ between
   two runs. A block of a list of the policy by_stack is named by its stack
   and its rank there; another block, by its description.

   The analysis with -eva-hit-log is the last of the three analyses of the
   observer. When it ends, the device prints its tables, then whether they
   are those of the analysis of the run without memexec, the reference,
   which ended before, or the tables of the reference if not. *)

let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  String.map (fun c -> if c = '\n' then ' ' else c) (Buffer.contents buffer)

let pp_kind fmt = function
  | Base.Malloc -> Format.pp_print_string fmt "malloc"
  | Base.VLA -> Format.pp_print_string fmt "variable-length array"
  | Base.Alloca -> Format.pp_print_string fmt "alloca"

let describe base =
  match base with
  | Base.Allocated (vi, kind, validity) ->
    Format.asprintf "%s, record %s, type %s, %a"
      (if Base.is_weak base then "weak" else "strong")
      (one_line Base.pretty_validity validity)
      (one_line Printer.pp_typ vi.vtype) pp_kind kind
  | _ -> "not allocated"

let callstack cs = one_line Eva.Callstack.pretty cs

(* The lines that describe the tables of the current project, sorted. *)
let tables () =
  let by_stack =
    Eva__Builtins_malloc.fold_malloced_by_stack
      (fun stack bases acc -> (stack, bases) :: acc) []
  in
  let names = Base.Hashtbl.create 17 in
  List.iter
    (fun (stack, bases) ->
       List.iteri
         (fun rank base ->
            Base.Hashtbl.replace names base
              (Printf.sprintf "block %d of %s" rank (callstack stack)))
         bases)
    by_stack;
  let lists =
    List.map
      (fun (stack, bases) ->
         Printf.sprintf "list of %s: %s" (callstack stack)
           (String.concat "; "
              (List.mapi
                 (fun rank base -> Printf.sprintf "%d: %s" rank (describe base))
                 bases)))
      by_stack
  in
  let owners =
    Eva__Builtins_malloc.fold_dynamic_bases
      (fun base owner acc ->
         let name =
           match Base.Hashtbl.find_opt names base with
           | Some name -> name
           | None -> "block " ^ describe base
         in
         Printf.sprintf "%s: owned by %s" name (callstack owner) :: acc)
      []
  in
  List.sort compare lists @ List.sort compare owners

let reference = ref None

let print lines =
  List.iter (fun line -> Format.printf "  %s@." line) lines

let () =
  Eva.Analysis.register_computation_hook ~on:Eva.Analysis.Computed
    (fun _ ->
       let lines = tables () in
       match Project.get_name (Project.current ()) with
       | "reference" -> reference := Some lines
       | "memexec" -> ()
       | _ ->
         Format.printf "Tables of the allocated blocks after the analysis \
                        with -eva-hit-log:@.";
         print lines;
         match !reference with
         | None -> Format.printf "No tables of the run without memexec.@."
         | Some reference when reference = lines ->
           Format.printf "These are the tables of the run without memexec.@."
         | Some reference ->
           Format.printf "They differ from those of the run without \
                          memexec:@.";
           print reference)
