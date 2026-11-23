(* Makes the requests before and after P in set, joined and on each
   callstack, after an analysis with -eva-hit-log, then sets
   -eva-initialized-locals and analyses again in the same project, and makes
   the same requests. The memoised answers of the first analysis must not
   be served after the second one: the answers on x change. *)

open Eva

let only_x state =
  let is_x base =
    match Base.to_varinfo base with
    | vi -> vi.Cil_types.vname = "x"
    | exception Base.Not_a_C_variable -> false
  in
  Format.asprintf "%a" Cvalue.Model.pretty (Cvalue.Model.filter_base is_x state)

let answers title =
  let kf = Globals.Functions.find_by_name "set" in
  let p = !(Kernel_function.find_label kf "P") in
  List.concat_map
    (fun (point, request) ->
       let joined = Results.get_cvalue_model request |> only_x in
       let states =
         Results.by_callstack request
         |> List.map (fun (_, r) -> Results.get_cvalue_model r |> only_x)
         |> List.sort String.compare
       in
       Format.printf "%s, %s, joined: %s@." title point joined;
       List.iteri (fun i s -> Format.printf "  callstack %d: %s@." i s) states;
       joined :: states)
    [ "before P", Results.before p; "after P", Results.after p ]

let main () =
  Analysis.compute ();
  let first = answers "Without -eva-initialized-locals" in
  begin match (Typed_parameter.get "-eva-initialized-locals").accessor with
    | Bool (accessor, _) -> accessor.set true
    | String _ | Int _ | Float _ -> assert false
  end;
  Analysis.compute ();
  let second = answers "With -eva-initialized-locals" in
  Format.printf "The answers changed with the second analysis: %b.@."
    (first <> second)

let () = Boot.Main.extend main
