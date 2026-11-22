(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* Probe of the campaign of dev/hit-log-cost/run.sh, loaded with -load-module
   into an unmodified frama-c. It notes the wall-clock time, the processor
   time and the counters of the garbage collector at the boundaries of the
   phases of an analysis by Eva, through public hooks only, so that it acts
   alike on every revision measured. The marks are written at exit to the
   file named by the environment variable HIT_LOG_COST_PHASES, one per line,
   separated by tabulations: name, wall-clock time (s, since the epoch),
   processor time (s), then the fields of [Gc.quick_stat] listed in
   [header]. The marks:
   - loaded: when the module is loaded, before the files are parsed;
   - parsed: when the AST has been computed;
   - iteration start: when Eva starts its iteration ([Computing]), after its
     preparation;
   - iteration end: when the iteration ends ([Computed]), before the passes
     that Eva runs after it;
   - eva end: when the main function of Eva returns;
   - exit: at the exit of the process. *)

let marks = ref []

let mark name =
  let gc = Gc.quick_stat () in
  let wall = Unix.gettimeofday () in
  let cpu = Sys.time () in
  marks := (name, wall, cpu, gc) :: !marks

let header =
  "mark\twall\tcpu\tminor_words\tpromoted_words\tmajor_words\t\
   minor_collections\tmajor_collections\theap_words\ttop_heap_words\t\
   compactions"

let print_mark out (name, wall, cpu, (gc: Gc.stat)) =
  Printf.fprintf out "%s\t%.6f\t%.6f\t%.0f\t%.0f\t%.0f\t%d\t%d\t%d\t%d\t%d\n"
    name wall cpu gc.minor_words gc.promoted_words gc.major_words
    gc.minor_collections gc.major_collections gc.heap_words gc.top_heap_words
    gc.compactions

let write () =
  match Sys.getenv_opt "HIT_LOG_COST_PHASES" with
  | None | Some "" -> ()
  | Some file ->
    let out = open_out file in
    output_string out header;
    output_char out '\n';
    List.iter (print_mark out) (List.rev !marks);
    close_out out

let () =
  mark "loaded";
  Ast.apply_after_computed (fun _ -> mark "parsed");
  Eva.Analysis.register_computation_hook
    (function
      | Computing -> mark "iteration start"
      | Computed -> mark "iteration end"
      | Aborted -> mark "aborted"
      | NotComputed -> ());
  Boot.Main.extend (fun () -> mark "eva end");
  at_exit (fun () -> mark "exit"; write ())
