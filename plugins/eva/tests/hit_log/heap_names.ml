(* Device of the tests of the reuse of calls that allocate with calloc,
   realloc and reallocarray (#129).

   When an analysis of any project ends, it lists the names of the blocks
   that the policy by_stack made on each stack, by rank, without the
   numeric suffix that the kernel adds to a name already used: this suffix
   differs between two runs. The name of a block made by the policy tells
   the builtin that created it (__malloc, __calloc or __realloc), the
   function that called the builtin and the line of the call, and whether
   the block became weak (_w after the builtin).

   The analysis with -eva-hit-log is the last of the three analyses of the
   observer. When it ends, the device prints its names, then whether they
   are those of the analysis of the run without memexec, the reference,
   which ended before, or the names of the reference if not. *)

let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  String.map (fun c -> if c = '\n' then ' ' else c) (Buffer.contents buffer)

(* The name of [base] without the suffix "_N" that Cabs2cil.fresh_global
   adds, N being a number. *)
let name base =
  let name =
    match base with
    | Base.Allocated (vi, _, _) -> vi.Cil_types.vname
    | _ -> Format.asprintf "%a" Base.pretty base
  in
  match String.rindex_opt name '_' with
  | Some i
    when i + 1 < String.length name
      && String.for_all
           (fun c -> c >= '0' && c <= '9')
           (String.sub name (i + 1) (String.length name - i - 1)) ->
    String.sub name 0 i
  | Some _ | None -> name

(* The lines that list the names of the blocks of the current project,
   sorted. *)
let names () =
  Eva__Builtins_malloc.fold_malloced_by_stack
    (fun stack bases acc ->
       Printf.sprintf "names on %s: %s" (one_line Eva.Callstack.pretty stack)
         (String.concat "; "
            (List.mapi (fun rank b -> Printf.sprintf "%d: %s" rank (name b))
               bases))
       :: acc)
    []
  |> List.sort compare

let reference = ref None

let print lines =
  List.iter (fun line -> Format.printf "  %s@." line) lines

let () =
  Eva.Analysis.register_computation_hook ~on:Eva.Analysis.Computed
    (fun _ ->
       let lines = names () in
       match Project.get_name (Project.current ()) with
       | "reference" -> reference := Some lines
       | "memexec" -> ()
       | _ ->
         Format.printf "Names of the blocks of the policy by_stack after the \
                        analysis with -eva-hit-log:@.";
         print lines;
         match !reference with
         | None -> Format.printf "No names of the run without memexec.@."
         | Some reference when reference = lines ->
           Format.printf "These are the names of the run without memexec.@."
         | Some reference ->
           Format.printf "They differ from those of the run without \
                          memexec:@.";
           print reference)
