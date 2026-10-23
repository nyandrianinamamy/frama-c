(* To test how arguments are transmitted (quoting, etc), we print some of them,
   but not all: we must filter the ones randomly chosen by Frama-Smith. *)
let () =
  let n =
    match Sys.getenv_opt "PRINT_UP_TO" with
    | None -> Array.length Sys.argv
    | Some s -> int_of_string s
  in
  for i = 1 to n do
    Format.printf "%d: [%s]@." i (Array.get Sys.argv i)
  done;
  exit 0
