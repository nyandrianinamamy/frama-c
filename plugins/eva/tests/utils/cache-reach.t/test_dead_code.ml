(* Test module of cache-reach.t: sends the server request getDeadCode on
   body, in a process that loads a session saved after an analysis, and
   prints the response with the statements in the source syntax. *)

module Printer_tag = Server.Printer_tag
module Kernel_ast = Server.Kernel_ast

(* The markers of the response, such as #s12, replaced by their text. *)
let replace_markers =
  let regexp = Str.regexp {|code:#[A-Za-z][0-9]+|} in
  let subst text =
    let id = Str.matched_string text in
    try Format.asprintf "%a" Printer_tag.pp_localizable (Kernel_ast.Marker.find id)
    with Not_found -> id
  in
  Str.global_substitute regexp subst

let rec pp_json fmt = function
  | `String s ->
    let s = replace_markers s in
    Format.pp_print_string fmt (String.map (function '\n' -> ' ' | c -> c) s)
  | `List list ->
    Pretty_utils.pp_list ~pre:"@[<hv 2>[ " ~sep:",@ " ~suf:" ]@]" ~empty:"[]"
      pp_json fmt list
  | `Assoc list ->
    let pp_entry fmt (key, v) = Format.fprintf fmt "%s: %a" key pp_json v in
    Pretty_utils.pp_list ~pre:"@[<hv 2>{ " ~sep:",@ " ~suf:" }@]" ~empty:"{}"
      pp_entry fmt list
  | json -> Format.pp_print_string fmt (Yojson.Basic.to_string json)

let dead_code () =
  let kf = Globals.Functions.find_by_name "body" in
  let data = Kernel_ast.Decl.to_json (Printer_tag.SFunction kf) in
  match Server.Main.find "plugins.eva.ast.getDeadCode" with
  | None -> Format.printf "no request getDeadCode@."
  | Some (_kind, handler) ->
    Format.printf "@[<v 2>getDeadCode body:@ %a@]@." pp_json (handler data)

let () = Boot.Main.extend dead_code
