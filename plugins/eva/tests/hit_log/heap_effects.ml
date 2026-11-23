(* Device of the tests of the heap effects (#121).

   In the analysis with -eva-hit-log, when a call of a function with a body
   ends, it prints the heap effects that the call received, in the order of
   their emission, each with the statement of the function of the call where
   it happens and, if it was emitted during a call made there, the function
   of that call. For an allocation, it also prints the suffix of its stack
   below the callstack of the call: the calls from the call down to the
   allocation, innermost first; or, if the stack of the allocation stops
   above the call, by how many calls.

   After the analyses, it prints the number of heap effects emitted in the
   whole run, in any project, whether the hit log records them or not. *)

let emitted = ref 0

let () = Eva__Heap_effects.register_sink (fun ?point:_ _ -> incr emitted)

let rec drop n list = if n <= 0 then list else drop (n - 1) (List.tl list)

let rec take n list =
  if n <= 0 then [] else List.hd list :: take (n - 1) (List.tl list)

let pretty_call fmt (kf, stmt) =
  Format.fprintf fmt "%a :: %a"
    Kernel_function.pretty kf Fileloc.pretty (Cil_datatype.Stmt.loc stmt)

let pretty_suffix ~(call: Eva.Callstack.t) fmt (stack: Eva.Callstack.t) =
  let below = List.length stack.stack - List.length call.stack in
  if below >= 0
  && Eva.Callstack.equal { stack with stack = drop below stack.stack } call
  then
    if below = 0 then Format.pp_print_string fmt "suffix empty"
    else
      Format.fprintf fmt "suffix %a"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.pp_print_string fmt " <- ")
           pretty_call)
        (take below stack.stack)
  else
    Format.fprintf fmt "stack above the call by %d" (- below)

let pretty_point fmt = function
  | None -> Format.pp_print_string fmt "no statement"
  | Some stmt -> Fileloc.pretty fmt (Cil_datatype.Stmt.loc stmt)

(* One effect on one line, whatever its length. *)
let one_line pp x =
  let buffer = Buffer.create 160 in
  let fmt = Format.formatter_of_buffer buffer in
  Format.pp_set_margin fmt 10_000;
  Format.pp_set_max_indent fmt 9_999;
  Format.fprintf fmt "%a@?" pp x;
  Buffer.contents buffer

let print_effects callstack effects =
  if Kernel_function.is_definition (Eva.Callstack.top_kf callstack) then begin
    Format.printf "Heap effects received by %s:@."
      (one_line Eva.Callstack.pretty callstack);
    let none = ref true in
    Eva__Hit_log.iter_effects
      (fun point callee e ->
         none := false;
         let pp fmt () =
           Format.fprintf fmt "%a%a: %a%t"
             pretty_point point
             (fun fmt -> function
                | None -> ()
                | Some kf ->
                  Format.fprintf fmt ", in %a" Kernel_function.pretty kf)
             callee
             Eva__Heap_effects.pretty e
             (fun fmt ->
                match e with
                | Allocation { stack; _ } ->
                  Format.fprintf fmt ", %a" (pretty_suffix ~call:callstack) stack
                | Mutation _ | Removal _ | Sweep _ -> ())
         in
         Format.printf "  %s@." (one_line pp ()))
      effects;
    if !none then Format.printf "  none@."
  end

let () = Eva__Hit_log.register_effects_hook print_effects

let () =
  Boot.Main.extend
    (fun () -> Format.printf "Heap effects emitted in the run: %d.@." !emitted)
