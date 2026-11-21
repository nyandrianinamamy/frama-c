(* Requests of Eva.Results after an analysis with -eva-hit-log, in the
   project, in a copy of it, and in the project saved and loaded. *)

open Eva

let shown base =
  match Base.to_varinfo base with
  | vi -> not (Cil.is_in_libc vi.vattr)
  | exception Base.Not_a_C_variable -> false

let pretty_answer fmt = function
  | Ok Cvalue.Model.Top | Error (Results.Top | DisabledDomain) ->
    Format.pp_print_string fmt "unavailable"
  | Error Results.Bottom -> Format.pp_print_string fmt "unreachable"
  | Ok state -> Cvalue.Model.pretty fmt (Cvalue.Model.filter_base shown state)

(* The states of two projects are compared by inclusion: their bases are
   equal, but not physically. *)
let equal_answer a b =
  match a, b with
  | Ok a, Ok b -> Cvalue.Model.(is_included a b && is_included b a)
  | Error a, Error b -> a = b
  | _ -> false

let string_of_callstack = Format.asprintf "%a" Legacy_read_trap.pretty_callstack

(* The answers at one point, joined and for each callstack, with their
   descriptions. *)
let point_answers description request =
  let callstacks =
    Results.callstacks request
    |> List.map (fun cs -> string_of_callstack cs, cs)
    |> List.sort compare
  in
  (description ^ ", joined", Results.get_cvalue_model_result request)
  :: List.map
    (fun (name, cs) ->
       description ^ ", " ^ name,
       Results.(request |> in_callstack cs |> get_cvalue_model_result))
    callstacks

(* The answers at the start of each function and before and after each of its
   statements. *)
let all_answers () =
  let of_function kf =
    let stmts = (Kernel_function.get_definition kf).sallstmts in
    let name = Kernel_function.get_name kf in
    let of_stmt stmt =
      let sid = string_of_int stmt.Cil_types.sid in
      point_answers (name ^ ", before " ^ sid) (Results.before stmt)
      @ point_answers (name ^ ", after " ^ sid) (Results.after stmt)
    in
    point_answers (name ^ ", start") (Results.at_start_of kf)
    @ List.concat_map of_stmt stmts
  in
  let main = Globals.Functions.find_by_name "main" in
  let f = Globals.Functions.find_by_name "f" in
  point_answers "initial state" Results.at_start
  @ of_function main @ of_function f

(* Makes the requests in the current project, and prints the report of the
   trap and, if [show], the answers before P. *)
let requests ~show name =
  Legacy_read_trap.start ();
  let answers = all_answers () in
  Legacy_read_trap.stop ();
  let reported = Legacy_read_trap.requests () in
  let reads = List.concat_map (fun r -> r.Legacy_read_trap.reads) reported in
  Format.printf "%s: %d answers; requests reported: %d; reads of the legacy \
                 store: %d.@."
    name (List.length answers) (List.length reported) (List.length reads);
  if show then begin
    let f = Globals.Functions.find_by_name "f" in
    let p = !(Kernel_function.find_label f "P") in
    List.iter
      (fun (description, answer) ->
         Format.printf "  @[<v 2>%s:@ %a@]@." description pretty_answer answer)
      (point_answers "f, before P" (Results.before p))
  end;
  answers

let compare_answers name answers name' answers' =
  let same =
    List.length answers = List.length answers'
    && List.for_all2
      (fun (d, a) (d', a') -> String.equal d d' && equal_answer a a')
      answers answers'
  in
  Format.printf "Answers of %s %s those of %s.@." name
    (if same then "equal" else "DIFFER FROM") name'

let in_project project f = Project.on project f ()

let main () =
  if Analysis.is_computed () then begin
    (* Loaded from the file saved by another process: compared with a new
       analysis of a copy. *)
    let loaded = requests ~show:true "loaded" in
    let again = Project.create_by_copy ~last:false "again" in
    let analyse () =
      Project.clear ~selection:(State_selection.with_dependencies Analysis.self)
        ();
      Analysis.compute ()
    in
    in_project again analyse;
    let answers = in_project again (fun () -> requests ~show:false "again") in
    compare_answers "loaded" loaded "again" answers
  end
  else begin
    Analysis.compute ();
    let original = requests ~show:true "original" in
    let copy = Project.create_by_copy ~last:false "copy" in
    let answers = in_project copy (fun () -> requests ~show:false "copy") in
    compare_answers "copy" answers "original" original;
    let file = Filename.temp_file "saved" ".sav" in
    Project.save (Filepath.of_string file);
    let loaded = Project.load (Filepath.of_string file) in
    Sys.remove file;
    let answers = in_project loaded (fun () -> requests ~show:false "loaded") in
    compare_answers "loaded" answers "original" original
  end

let () = Boot.Main.extend main
