(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* A new file follows each real statistics reset. Intermediate Computed
   notifications overwrite the current analysis snapshot. *)
let run () =
  let dir = Sys.getenv "EVA_COLLECTOR_STATS_DIR" in
  let runs = Project.Datatype.Hashtbl.create 3 in
  Eva.Cvalue_callbacks.register_at_start_hook (fun () ->
      let file = Filename.temp_file ~temp_dir:dir "analysis" ".tsv" in
      Project.Datatype.Hashtbl.replace runs (Project.current ()) file);
  Eva.Analysis.register_computation_hook (fun status ->
      let project = Project.current () in
      match status with
      | Computed | Aborted ->
        Option.iter
          (fun file ->
             Eva.Statistics.export_as_csv ~filename:(Filepath.of_string file) ();
             let state = if status = Computed then "completed" else "aborted" in
             let status_file = Filename.remove_extension file ^ ".status" in
             Out_channel.with_open_text status_file (fun out ->
                 Out_channel.output_string out (state ^ "\n")))
          (Project.Datatype.Hashtbl.find_opt runs project)
      | NotComputed -> Project.Datatype.Hashtbl.remove runs project
      | Computing -> ())

let () = run ()
