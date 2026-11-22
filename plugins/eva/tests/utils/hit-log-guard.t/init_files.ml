(* Builds the AST with no file on the command line, so that Kernel.Files
   stays empty:
   - with File.init_from_c_files, from the file named by the environment
     variable HIT_LOG_GUARD_INIT;
   - when HIT_LOG_GUARD_SYNTHETIC is 1, as the empty AST of no file, to which
     a global with a generated location is added: the AST then has a global
     and no source file. *)

let () =
  Boot.Main.extend
    (fun () ->
       match Sys.getenv_opt "HIT_LOG_GUARD_INIT" with
       | Some file when file <> "" ->
         File.init_from_c_files [ File.from_filename (Filepath.of_string file) ]
       | _ ->
         if Sys.getenv_opt "HIT_LOG_GUARD_SYNTHETIC" = Some "1" then begin
           let ast = Ast.get () in
           let vi =
             Cil.makeGlobalVar ~source:false "synthetic" Cil_const.intType
           in
           let loc = Fileloc.generated "hit_log_guard" in
           ast.Cil_types.globals <- Cil_types.GVarDecl (vi, loc) :: ast.globals
         end)
