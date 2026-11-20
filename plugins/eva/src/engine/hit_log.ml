(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Stmt = Cil_datatype.Stmt

type state = Cvalue_domain.State.t

type kind =
  | Body of int
  | Hit of int
  | Spec
  | Builtin of string
  | Unresolved

type invocation = {
  stack: Callstack.t;
  input: state;
  mutable kind: kind;
}

type points = {
  before: state Stmt.Hashtbl.t;
  after: state Stmt.Hashtbl.t;
}

type producer = {
  kf: Kernel_function.t;
  complete: bool; (* whether its analysis reached its fixpoint *)
  entries: state list;
  points: points option;
}

type completion = Recording | Complete | Interrupted

(* The records of one analysis. They are plain tables shared by all
   projects; [Current] ties them to the results of one project. *)
type log = {
  stamp: int;
  exact: bool;
  states: bool; (* whether states are recorded at all *)
  mutable consistent: bool;
  mutable completion: completion;
  mutable initial: (Callstack.t * state) option;
  invocations: invocation list Callstack.Hashtbl.t; (* latest first *)
  producers: (int, producer) Hashtbl.t;
  no_results: unit Kernel_function.Hashtbl.t;
  mutable open_calls: invocation list; (* innermost first *)
}

let create stamp ~exact ~states = {
  stamp; exact; states;
  consistent = true;
  completion = Recording;
  initial = None;
  invocations = Callstack.Hashtbl.create 17;
  producers = Hashtbl.create 17;
  no_results = Kernel_function.Hashtbl.create 7;
  open_calls = [];
}

let current = ref (create 0 ~exact:false ~states:false)
let last_stamp = ref 0

(* The stamp of the records of the current results, set when the analysis
   starts. It is cleared with the results of Eva and never saved: after a
   load, the records of the process do not describe the loaded results. *)
module Current =
  State_builder.Option_ref
    (Datatype.Int)
    (struct
      let name = "Eva.Hit_log.Current"
      let dependencies = [ Self.state ]
    end)

let () = Current.howto_marshal (fun _ -> None) ref

(* ----- Recording ---------------------------------------------------------- *)

let start ~exact ~states =
  incr last_stamp;
  current := create !last_stamp ~exact ~states;
  if exact then Current.set !last_stamp

let seal () =
  let log = !current in
  if log.exact && log.completion = Recording then begin
    if log.open_calls <> [] then log.consistent <- false;
    log.completion <- Complete
  end

(* The invocations still open are those that the analysis interrupted. *)
let interrupt () =
  let log = !current in
  if log.exact && log.completion = Recording
  then log.completion <- Interrupted

let recording () =
  let log = !current in
  log.exact && log.completion = Recording

let initial stack state =
  if recording () then (!current).initial <- Some (stack, state)

let enter stack input =
  if recording () then
    let log = !current in
    let invocation = { stack; input; kind = Unresolved } in
    let visits =
      Option.value ~default:[] (Callstack.Hashtbl.find_opt log.invocations stack)
    in
    Callstack.Hashtbl.replace log.invocations stack (invocation :: visits);
    log.open_calls <- invocation :: log.open_calls

(* The innermost open invocation, which must be on [stack]. When an analysis
   stops, the innermost invocations are not closed: unless [strict], the
   open invocation on [stack] is looked for below them. *)
let open_invocation ?(strict = true) stack =
  let log = !current in
  let on_stack invocation = Callstack.equal invocation.stack stack in
  match log.open_calls with
  | invocation :: _ when on_stack invocation -> Some invocation
  | calls ->
    let found = if strict then None else List.find_opt on_stack calls in
    if Option.is_none found then log.consistent <- false;
    found

let leave stack =
  if recording () then
    let log = !current in
    match log.open_calls with
    | invocation :: tail when Callstack.equal invocation.stack stack ->
      log.open_calls <- tail
    | _ -> log.consistent <- false

let hit stack ~producer =
  if recording () then
    Option.iter (fun invocation -> invocation.kind <- Hit producer)
      (open_invocation stack)

let interpreted stack kind =
  if recording () then
    let kind = match kind with `Spec -> Spec | `Builtin name -> Builtin name in
    Option.iter (fun invocation -> invocation.kind <- kind)
      (open_invocation stack)

let body stack ~producer ~complete ~entries ~points =
  if recording () then
    match open_invocation ~strict:complete stack with
    | None -> ()
    | Some invocation ->
      let log = !current in
      let kf = Callstack.top_kf stack in
      let points =
        if log.states then begin
          if Option.is_none points
          then Kernel_function.Hashtbl.replace log.no_results kf ();
          Option.map Lazy.force points
        end
        else None
      in
      Hashtbl.replace log.producers producer { kf; complete; entries; points };
      invocation.kind <- Body producer

(* ----- Resolver ----------------------------------------------------------- *)

type unavailable = Pending | Interrupted | Not_recorded

type answer =
  | Reached of state
  | Unreachable
  | Not_analyzed
  | Unavailable of unavailable

type reach = Reaching | Not_reaching | Unknown of unavailable

let wrong_producer = ref false
let set_wrong_producer_control b = wrong_producer := b

let usable () =
  let log = !current in
  log.exact && log.consistent && Current.get_option () = Some log.stamp

(* The visits on [stack], in the order of the analysis. *)
let visits stack =
  Callstack.Hashtbl.find_opt (!current).invocations stack
  |> Option.value ~default:[] |> List.rev

let is_hit invocation =
  match invocation.kind with
  | Hit _ -> true
  | Body _ | Spec | Builtin _ | Unresolved -> false

(* A hit skips the body of the callee: nothing is recorded for the stacks
   below it. *)
let rec below_hit stack =
  match Callstack.pop stack with
  | None -> false
  | Some caller -> List.exists is_hit (visits caller) || below_hit caller

(* The visits of [kf] on [stack]. *)
let visits_of kf stack =
  if Kernel_function.equal (Callstack.top_kf stack) kf then visits stack else []

(* All the invocations of [kf], on every callstack. *)
let invocations_of log kf =
  Callstack.Hashtbl.fold
    (fun stack visits acc ->
       if Kernel_function.equal (Callstack.top_kf stack) kf
       then visits @ acc else acc)
    log.invocations []

let has_hits log =
  Callstack.Hashtbl.fold
    (fun _ visits acc -> acc || List.exists is_hit visits)
    log.invocations false

(* The producer that rebuilds a body visit. *)
let producer_of log kf id =
  if !wrong_producer then
    let first id' producer acc =
      if Kernel_function.equal producer.kf kf && id' < fst acc
      then id', Some producer else acc
    in
    snd (Hashtbl.fold first log.producers (max_int, None))
  else Hashtbl.find_opt log.producers id

(* Raised when the records cannot answer: the request reads the legacy
   store. *)
exception Decline

(* In an interrupted analysis, later visits could reach a point that no
   visit has reached so far. A body interpreted by its specification stays
   so on the same callstack. *)
let settle log answer =
  match answer, log.completion with
  | Unreachable, Interrupted -> Unavailable Interrupted
  | _ -> answer

(* An invocation that the analysis has not interpreted. *)
let unresolved log =
  match log.completion with
  | Recording -> Unavailable Pending
  | Interrupted -> Unavailable Interrupted
  | Complete -> raise Decline

(* The answer of one visit at a statement. A missing state is unreachable
   only in a complete producer. *)
let visit_answer log point stmt kf invocation =
  match invocation.kind with
  | Hit _ -> raise Decline
  | Spec | Builtin _ -> Not_analyzed
  | Unresolved -> unresolved log
  | Body id ->
    match producer_of log kf id with
    | None -> raise Decline
    | Some { points = None; _ } -> Unavailable Not_recorded
    | Some { points = Some points; complete; _ } ->
      let table =
        match point with
        | Domain_store.Before _ -> points.before
        | _ -> points.after
      in
      match Stmt.Hashtbl.find_opt table stmt with
      | Some state -> Reached state
      | None -> if complete then Unreachable else Unavailable Interrupted

(* Joins the answers of the visits on one callstack, in the order of the
   analysis, as the legacy store joins their states. An unavailable visit
   makes the whole callstack unavailable. *)
let join_answers answers =
  let join acc answer =
    match acc, answer with
    | Unavailable r, _ | _, Unavailable r -> Unavailable r
    | Reached a, Reached b -> Reached (Cvalue_domain.State.join a b)
    | Reached s, (Unreachable | Not_analyzed)
    | (Unreachable | Not_analyzed), Reached s -> Reached s
    | Unreachable, _ | _, Unreachable -> Unreachable
    | Not_analyzed, Not_analyzed -> Not_analyzed
  in
  match answers with
  | [] -> Unreachable
  | first :: others -> List.fold_left join first others

(* Answers that do not depend on the callstack, as the analysis status
   decides them in the legacy store. Without recorded states, the points of
   an analyzed body, the start of a called function and the initial state
   are unavailable. *)
let function_level log point =
  let analyzed kf =
    List.exists (fun v -> match v.kind with
        | Body _ | Hit _ | Unresolved -> true
        | Spec | Builtin _ -> false)
      (invocations_of log kf)
  in
  match point with
  | Domain_store.Initial ->
    if log.states then None else Some (Unavailable Not_recorded)
  | Start kf ->
    if log.states || invocations_of log kf = [] then None
    else Some (Unavailable Not_recorded)
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    if not log.states && analyzed kf
    || Kernel_function.Hashtbl.mem log.no_results kf
    then Some (Unavailable Not_recorded)
    else None

(* The answer on [stack], with the visits used. *)
let classify_on log stack (point : Domain_store.control_point) =
  match log.completion with
  | Recording -> Unavailable Pending, []
  | Complete | Interrupted ->
    match function_level log point with
    | Some answer -> answer, []
    | None ->
      match point with
      | Initial ->
        let answer =
          match log.initial with
          | Some (stack', state) when Callstack.equal stack stack' ->
            Reached state
          | Some _ -> Unreachable
          | None -> settle log Unreachable
        in
        answer, []
      | Start kf ->
        if below_hit stack then raise Decline;
        let visits = visits_of kf stack in
        let answers = List.map (fun v -> Reached v.input) visits in
        settle log (join_answers answers), visits
      | Before stmt | After stmt ->
        if below_hit stack then raise Decline;
        let kf = Kernel_function.find_englobing_kf stmt in
        let visits = visits_of kf stack in
        let answers = List.map (visit_answer log point stmt kf) visits in
        settle log (join_answers answers), visits

let pretty_kind fmt = function
  | Body id -> Format.fprintf fmt "body#%d" id
  | Hit id -> Format.fprintf fmt "hit#%d" id
  | Spec -> Format.pp_print_string fmt "spec"
  | Builtin name -> Format.fprintf fmt "builtin %s" name
  | Unresolved -> Format.pp_print_string fmt "unresolved"

let pretty_kinds visits fmt =
  match visits with
  | [] -> Format.pp_print_string fmt "none"
  | _ ->
    Pretty_utils.pp_list ~sep:"," pretty_kind fmt
      (List.map (fun v -> v.kind) visits)

let classify ~callstack point =
  if not (usable ()) then None
  else
    match classify_on !current callstack point with
    | exception Decline -> None
    | answer, _visits -> Some answer

let resolve ~callstack point =
  if not (usable ()) then None
  else
    match classify_on !current callstack point with
    | exception Decline -> None
    | answer, visits ->
      Legacy_read_guard.resolved
        (Domain_store.pretty_read_point ~callstack point)
        (pretty_kinds visits);
      match answer with
      | Reached state -> Some (`Value state)
      | Unreachable | Not_analyzed -> Some `Bottom
      | Unavailable _ -> Some `Top

(* Whether one callstack reaches [point]. A visit that reaches it is
   enough, whatever the other visits. *)
let reach_on log stack point =
  let reaching =
    match point with
    | Domain_store.Initial | Start _ -> false
    | Before stmt | After stmt ->
      log.completion <> Recording
      && function_level log point = None
      && not (below_hit stack)
      &&
      let kf = Kernel_function.find_englobing_kf stmt in
      List.exists
        (fun visit ->
           match visit_answer log point stmt kf visit with
           | Reached _ -> true
           | _ -> false
           | exception Decline -> false)
        (visits_of kf stack)
  in
  if reaching then `Reaching
  else
    match fst (classify_on log stack point) with
    | Reached _ -> `Reaching
    | Unreachable | Not_analyzed -> `Not_reaching
    | Unavailable r -> `Unknown r
    | exception Decline -> `Decline

(* The callstacks of the records at [point]. *)
let recorded_stacks log (point : Domain_store.control_point) =
  match point with
  | Initial -> Option.to_list (Option.map fst log.initial)
  | Start kf -> invocations_of log kf |> List.map (fun v -> v.stack)
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    invocations_of log kf |> List.map (fun v -> v.stack)

let reach ?callstacks ?(filter = fun _ -> true) point =
  if not (usable ()) then None
  else
    let log = !current in
    let supplied = Option.is_some callstacks in
    let stacks =
      match callstacks with
      | Some stacks -> stacks
      | None -> recorded_stacks log point |> List.sort_uniq Callstack.compare
    in
    let stacks = List.filter filter stacks in
    let answer =
      match log.completion, function_level log point with
      | Recording, _ -> Some (Unknown Pending)
      | _, Some (Unavailable r) -> Some (Unknown r)
      | _ ->
        let answers = List.map (fun stack -> reach_on log stack point) stacks in
        let unknown =
          List.find_map (function `Unknown r -> Some r | _ -> None) answers
        in
        if List.mem `Reaching answers then Some Reaching
        else if List.mem `Decline answers then None
        else if Option.is_some unknown then Some (Unknown (Option.get unknown))
        else if not supplied && has_hits log then
          (* A function called below a hit has no recorded invocation. *)
          None
        else if stacks = [] && log.completion = Interrupted
        then Some (Unknown Interrupted)
        else Some Not_reaching
    in
    Option.iter (fun _ ->
        Legacy_read_guard.resolved
          (Domain_store.pretty_read_point point)
          (fun fmt ->
             Format.fprintf fmt "%d callstack(s)" (List.length stacks)))
      answer;
    answer

let pretty_unavailable fmt = function
  | Pending -> Format.pp_print_string fmt "pending"
  | Interrupted -> Format.pp_print_string fmt "interrupted"
  | Not_recorded -> Format.pp_print_string fmt "not recorded"

let pretty_answer fmt = function
  | Reached _ -> Format.pp_print_string fmt "reached"
  | Unreachable -> Format.pp_print_string fmt "unreachable"
  | Not_analyzed -> Format.pp_print_string fmt "body not analyzed"
  | Unavailable r -> Format.fprintf fmt "unavailable (%a)" pretty_unavailable r

let pretty_reach fmt = function
  | Reaching -> Format.pp_print_string fmt "reaching"
  | Not_reaching -> Format.pp_print_string fmt "not reaching"
  | Unknown r -> Format.fprintf fmt "unknown (%a)" pretty_unavailable r

let pretty_visits fmt stack =
  let log = !current in
  let pretty_visit fmt invocation =
    let entries =
      match invocation.kind with
      | Body id ->
        begin match Hashtbl.find_opt log.producers id with
          | Some { entries = []; _ } -> "no entry survives the preconditions"
          | Some { entries; _ } ->
            Format.asprintf "%d entries survive the preconditions"
              (List.length entries)
          | None -> "no producer"
        end
      | Hit _ | Spec | Builtin _ | Unresolved -> "no body analysis"
    in
    Format.fprintf fmt "@[<v 2>%a: %s; input:@ %a@]"
      pretty_kind invocation.kind entries
      Cvalue.Model.pretty (fst invocation.input)
  in
  Pretty_utils.pp_list ~sep:"@\n" pretty_visit fmt (visits stack)
