(* Analyses consolidation.c with Eva.Legacy_read_trap on. Prints the requests
   and the reads of the legacy store that the trap reports when the hook run
   when Eva has results starts, then at the end of the analysis, by pass, and
   whether the legacy store holds a joined state before S in f. *)

open Eva

let outside = "outside the passes"

(* The number of requests, of reads in them and of reads outside any request
   reported by the trap, by pass, in the order of their first report. *)
let by_pass () =
  let add acc name (requests, reads, strays) =
    let r, d, s = Option.value ~default:(0, 0, 0) (List.assoc_opt name acc) in
    let counts = r + requests, d + reads, s + strays in
    if List.mem_assoc name acc
    then List.map (fun (n, c) -> n, if n = name then counts else c) acc
    else acc @ [ name, counts ]
  in
  let acc =
    List.fold_left
      (fun acc r ->
         let name = Option.value ~default:outside r.Legacy_read_trap.pass in
         add acc name (1, List.length r.reads, 0))
      [] (Legacy_read_trap.requests ())
  in
  List.fold_left
    (fun acc s ->
       let name = Option.value ~default:outside s.Legacy_read_trap.in_pass in
       add acc name (0, 0, 1))
    acc (Legacy_read_trap.stray_reads ())

let print_report title =
  let passes = by_pass () in
  let total =
    List.fold_left
      (fun (r, d, s) (_, (r', d', s')) -> r + r', d + d', s + s')
      (0, 0, 0) passes
  in
  let print (r, d, s) =
    Format.printf "%d requests, %d reads of the legacy store in them, %d \
                   reads outside any request" r d s
  in
  Format.printf "@[<v 2>%s: " title;
  print total;
  List.iter
    (fun (name, counts) -> Format.printf "@ %s: " name; print counts)
    passes;
  Format.printf "@]@."

let () =
  Analysis.register_computation_hook ~on:Computed
    (fun _ ->
       print_report
         "Reported from the end of the iteration to the hook run when Eva \
          has results")

let main () =
  Format.printf "Recording: %b.@." (Parameters.HitLog.get ());
  Legacy_read_trap.start ();
  Analysis.compute ();
  print_report "Reported at the end of the analysis";
  Legacy_read_trap.stop ();
  let f = Globals.Functions.find_by_name "f" in
  let stmt = !(Kernel_function.find_label f "S") in
  let joined =
    match Eva__Cvalue_results.get_state (Before stmt) with
    | `Value _ -> "yes"
    | `Bottom | `Top -> "no"
  in
  Format.printf "Joined state before S in the legacy store: %s.@." joined

let () = Boot.Main.extend main
