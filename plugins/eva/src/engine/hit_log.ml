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

type guards = (bool * bool) Stmt.Hashtbl.t

type producer = {
  kf: Kernel_function.t;
  complete: bool; (* whether its analysis reached its fixpoint *)
  entries: state list;
  points: points option;
  guards: guards; (* recorded even when the states are not *)
}

type completion = Recording | Complete | Interrupted

type unavailable = Pending | Interrupted | Not_recorded

type answer =
  | Reached of state
  | Unreachable
  | Not_analyzed
  | Unavailable of unavailable

type reach = Reaching | Not_reaching | Unknown of unavailable

type 'a selection =
  | Known of (Callstack.t * 'a) list
  | Unknown_state of Callstack.t list

(* What the records tell of the callstacks at one point, once the analysis
   has ended. [order]: the callstacks on which the legacy store registers a
   state at the point, in its order. [stacks]: for each callstack, whether a
   visit reaches the point, and its classification, [None] if the resolver
   declines it. *)
type point_info = {
  order: Callstack.t list Lazy.t;
  stacks: (bool * answer option) Callstack.Hashtbl.t;
}

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
  by_kf: invocation list Kernel_function.Hashtbl.t;
  (* the invocations of each function, latest first *)
  mutable has_hit: bool;
  (* Answers computed once the analysis has ended. *)
  points: point_info Domain_store.ControlPoint.Hashtbl.t;
  consolidated:
    state Lattice_bounds.or_top_bottom Domain_store.ControlPoint.Hashtbl.t;
  mutable relations: Function_calls.relations option;
  (* The facts that the legacy tables register when the analysis chooses
     how to interpret a call, and on each fireable branch: the merged
     analysis status and the callers of each function, and the fireable
     branches of each conditional. *)
  statuses: Function_calls.analysis_status Kernel_function.Hashtbl.t;
  callers: Stmt.Set.t Kernel_function.Map.t Kernel_function.Hashtbl.t;
  fired: (bool * bool) Stmt.Hashtbl.t;
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
  by_kf = Kernel_function.Hashtbl.create 17;
  has_hit = false;
  points = Domain_store.ControlPoint.Hashtbl.create 17;
  consolidated = Domain_store.ControlPoint.Hashtbl.create 17;
  relations = None;
  statuses = Kernel_function.Hashtbl.create 17;
  callers = Kernel_function.Hashtbl.create 17;
  fired = Stmt.Hashtbl.create 17;
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
    let kf = Callstack.top_kf stack in
    let calls =
      Option.value ~default:[] (Kernel_function.Hashtbl.find_opt log.by_kf kf)
    in
    Kernel_function.Hashtbl.replace log.by_kf kf (invocation :: calls);
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
    Option.iter (fun invocation ->
        invocation.kind <- Hit producer;
        (!current).has_hit <- true)
      (open_invocation stack)

let interpreted stack kind =
  if recording () then
    let kind = match kind with `Spec -> Spec | `Builtin name -> Builtin name in
    Option.iter (fun invocation -> invocation.kind <- kind)
      (open_invocation stack)

let body stack ~producer ~complete ~entries ~points ~guards =
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
      Hashtbl.replace log.producers producer
        { kf; complete; entries; points; guards };
      invocation.kind <- Body producer

(* ----- Resolver ----------------------------------------------------------- *)

let wrong_producer = ref false
let set_wrong_producer_control b = wrong_producer := b

let decline = ref false
let set_decline_control b = decline := b

let usable () =
  let log = !current in
  not !decline
  && log.exact && log.consistent && Current.get_option () = Some log.stamp

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

(* All the invocations of [kf], on every callstack, latest first. *)
let invocations_of log kf =
  Option.value ~default:[] (Kernel_function.Hashtbl.find_opt log.by_kf kf)

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

(* The points whose states are unavailable on every callstack, as the
   analysis status decides them in the legacy store. Without recorded
   states, the points of an analyzed body, the start of a called function
   and the initial state are not recorded. *)
let function_level log point =
  let analyzed kf =
    List.exists (fun v -> match v.kind with
        | Body _ | Hit _ | Unresolved -> true
        | Spec | Builtin _ -> false)
      (invocations_of log kf)
  in
  match point with
  | Domain_store.Initial ->
    if log.states then None else Some Not_recorded
  | Start kf ->
    if log.states || invocations_of log kf = [] then None
    else Some Not_recorded
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    if not log.states && analyzed kf
    || Kernel_function.Hashtbl.mem log.no_results kf
    then Some Not_recorded
    else None

(* The answer on [stack], with the visits used. *)
let classify_on log stack (point : Domain_store.control_point) =
  match log.completion with
  | Recording -> Unavailable Pending, []
  | Complete | Interrupted ->
    match function_level log point with
    | Some reason -> Unavailable reason, []
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

let describes_results = usable

(* The initial state is final once recorded: it answers during the
   analysis too. *)
let initial_state () =
  if not (usable ()) then None
  else
    let log = !current in
    let answer =
      if not log.states then `Top
      else
        match log.initial with
        | Some (_stack, state) -> `Value state
        | None -> `Bottom
    in
    Legacy_read_guard.resolved
      (Domain_store.pretty_read_point Initial)
      (fun fmt -> Format.pp_print_string fmt "initialized globals");
    Some answer

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

let memo table point compute =
  match Domain_store.ControlPoint.Hashtbl.find_opt table point with
  | Some answer -> answer
  | None ->
    let answer = compute () in
    Domain_store.ControlPoint.Hashtbl.replace table point answer;
    answer

(* ----- Several callstacks ----------------------------------------------- *)

(* The legacy store registers the state of a control point on a callstack
   in a [Callstack.Hashtbl.create 7] per point, and enumerates the
   callstacks in the order of that table. [store_order] rebuilds the same
   table from the callstacks in the order of their first registration, and
   reads it back. *)
let store_order stacks =
  let table = Callstack.Hashtbl.create 7 in
  List.iter (fun stack -> Callstack.Hashtbl.replace table stack ()) stacks;
  Callstack.Hashtbl.to_seq_keys table |> List.of_seq

(* The callstacks on which the legacy store registers a state at [point],
   in the order of their first registration. The start of a function is
   registered at each call, before the body or the hit; the states of a
   statement when the analysis of a body that reaches it completes, in the
   order of the producer ids. *)
let registrations log (point : Domain_store.control_point) =
  let first_occurrences stacks =
    let seen = Callstack.Hashtbl.create 17 in
    List.filter (fun stack ->
        not (Callstack.Hashtbl.mem seen stack)
        && (Callstack.Hashtbl.add seen stack (); true))
      stacks
  in
  (* The invocations of [kf], in the order in which they were entered. *)
  let calls kf = List.rev (invocations_of log kf) in
  match point with
  | Initial -> Option.to_list (Option.map fst log.initial)
  | Start kf -> calls kf |> List.map (fun v -> v.stack) |> first_occurrences
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    let reaches id =
      match Hashtbl.find_opt log.producers id with
      | Some { points = Some points; _ } ->
        let table =
          match point with Before _ -> points.before | _ -> points.after
        in
        Stmt.Hashtbl.mem table stmt
      | Some { points = None; _ } | None -> false
    in
    let bodies =
      List.filter_map (fun v ->
          match v.kind with
          | Body id when reaches id -> Some (id, v.stack)
          | Body _ | Hit _ | Spec | Builtin _ | Unresolved -> None)
        (calls kf)
    in
    List.sort (fun (a, _) (b, _) -> Int.compare a b) bodies
    |> List.map snd |> first_occurrences

(* Whether a visit on [stack] reaches [point]. A visit that reaches it is
   positive evidence, whatever the other visits. *)
let visit_reaches log stack (point : Domain_store.control_point) =
  match point with
  | Initial | Start _ -> false
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

(* What the records tell of [stack] at [point]: whether a visit reaches
   the point, and the classification of the callstack, [None] when the
   resolver declines it. A callstack reaches the point if one of its
   visits does, even when the state of another visit, hence of the
   callstack, is unavailable. *)
let compute_stack_info log point stack =
  let answer =
    match classify_on log stack point with
    | answer, _visits -> Some answer
    | exception Decline -> None
  in
  let reaching =
    match answer with
    | Some (Reached _) -> true
    | _ -> visit_reaches log stack point
  in
  reaching, answer

(* The records at [point], memoized once the analysis has ended. *)
let point_info log point =
  memo log.points point (fun () ->
      { order = lazy (store_order (registrations log point));
        stacks = Callstack.Hashtbl.create 7 })

let stack_info log point stack =
  if log.completion = Recording then compute_stack_info log point stack
  else
    let info = point_info log point in
    match Callstack.Hashtbl.find_opt info.stacks stack with
    | Some answer -> answer
    | None ->
      let answer = compute_stack_info log point stack in
      Callstack.Hashtbl.replace info.stacks stack answer;
      answer

(* Whether one callstack reaches [point]. *)
let reach_on log stack point =
  match stack_info log point stack with
  | true, _ | false, Some (Reached _) -> `Reaching
  | false, Some (Unreachable | Not_analyzed) -> `Not_reaching
  | false, Some (Unavailable r) -> `Unknown r
  | false, None -> `Decline

(* The callstacks of the records at [point]. *)
let recorded_stacks log (point : Domain_store.control_point) =
  match point with
  | Initial -> Option.to_list (Option.map fst log.initial)
  | Start kf -> invocations_of log kf |> List.map (fun v -> v.stack)
  | Before stmt | After stmt ->
    let kf = Kernel_function.find_englobing_kf stmt in
    invocations_of log kf |> List.map (fun v -> v.stack)

(* The callstacks of a request: those supplied, by default those of the
   records at [point], that satisfy [filter]. *)
let selected_stacks log ?callstacks ~filter point =
  let stacks =
    match callstacks with
    | Some stacks -> stacks
    | None -> recorded_stacks log point |> List.sort_uniq Callstack.compare
  in
  List.filter filter stacks

(* A request that supplies its callstacks selects some of them: when its
   predicates reject each one, or when it supplies none, its selection is
   empty, whatever the analysis and the records of the rejected callstacks.
   No other callstack can contribute. *)
let empty_selection ~supplied stacks = supplied && stacks = []

(* After an interruption, the rest of the analysis could reach a point on a
   callstack that it has not entered, or below a memexec hit. When no
   selected callstack reaches the point, its answer is unknown, unless the
   request supplies its callstacks and the records classify each selected
   one.
   [declined]: the records do not classify some selected callstack. *)
let open_selection log ~supplied ~declined =
  log.completion = Interrupted && (not supplied || declined)

let reach ?callstacks ?(filter = fun _ -> true) point =
  if not (usable ()) then None
  else
    let log = !current in
    let supplied = Option.is_some callstacks in
    let stacks = selected_stacks log ?callstacks ~filter point in
    let answer =
      match log.completion, function_level log point with
      | _ when empty_selection ~supplied stacks -> Some Not_reaching
      | Recording, _ -> Some (Unknown Pending)
      | _, Some r -> Some (Unknown r)
      | (Complete | Interrupted), None ->
        let answers = List.map (fun stack -> reach_on log stack point) stacks in
        let unknown =
          List.find_map (function `Unknown r -> Some r | _ -> None) answers
        in
        let declined = List.mem `Decline answers in
        (* A function called below a hit has no recorded invocation. *)
        let hidden = not supplied && log.has_hit in
        if List.mem `Reaching answers then Some Reaching
        else if open_selection log ~supplied ~declined
        then Some (Unknown Interrupted)
        else if declined then None
        else if Option.is_some unknown then Some (Unknown (Option.get unknown))
        else if hidden then None
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

(* ----- Selections ------------------------------------------------------- *)

(* The selection of [stacks] at [point]. A selection that supplies its
   callstacks and keeps none of them is empty, as [empty_selection] tells;
   the rest of this comment concerns the other selections. The callstacks
   that reach the point come in the order of the legacy store: each visit
   that reaches it is positive evidence, whatever the others. Declines, so
   that the request reads the legacy store, when the records contain a
   memexec hit, since the callstacks below a hit and its points are not
   recorded yet; after an interruption, only when a selected callstack
   reaches the point, the selection being unknown or empty otherwise. Also
   declines when the records do not classify a selected callstack of a
   completed analysis. The state of the selection is known when the records
   give the state of each selected callstack that may reach the point:
   - while the analysis runs, or when the states at the point are not
     recorded, nothing is known and no callstack is enumerated, as on the
     legacy path;
   - a callstack whose state is unavailable, such as a callstack with an
     interrupted visit, makes the state of the selection unknown, even
     when one of its visits reaches the point;
   - after an interruption, the state of a callstack that reaches the
     point is what the analysis computed; a selection that no callstack
     reaches is unknown, as [open_selection] tells. *)
let selection_on log ~supplied stacks point =
  match log.completion, function_level log point with
  | _ when empty_selection ~supplied stacks -> Known []
  | Recording, _ | _, Some _ -> Unknown_state []
  | Complete, None when log.has_hit -> raise Decline
  | Interrupted, None
    when log.has_hit
      && List.exists (fun stack -> fst (stack_info log point stack)) stacks ->
    raise Decline
  | (Complete | Interrupted), None ->
    let infos =
      List.map (fun stack -> stack, stack_info log point stack) stacks
    in
    let reaching = List.exists (fun (_, (reaching, _)) -> reaching) infos in
    let declined =
      List.exists (function _, (_, None) -> true | _ -> false) infos
    in
    if declined && log.completion = Complete then raise Decline;
    let unavailable =
      List.exists (function _, (_, Some (Unavailable _)) -> true | _ -> false)
        infos
    in
    let unknown =
      declined || unavailable
      || not reaching && open_selection log ~supplied ~declined
    in
    let selected = Callstack.Hashtbl.create 7 in
    List.iter (fun (stack, (reaching, answer)) ->
        if reaching then Callstack.Hashtbl.replace selected stack answer)
      infos;
    let enumerated =
      List.filter_map (fun stack ->
          Option.map (fun answer -> stack, answer)
            (Callstack.Hashtbl.find_opt selected stack))
        (Lazy.force (point_info log point).order)
    in
    if unknown then Unknown_state (List.map fst enumerated)
    else
      Known
        (List.filter_map (function
             | stack, Some (Reached state) -> Some (stack, state)
             | _ -> None)
            enumerated)

(* The callstacks of a selection and the kinds of their visits. *)
let pretty_selection selection fmt =
  let pretty fmt stack =
    Format.fprintf fmt "%a:%t" Domain_store.pretty_callstack stack
      (pretty_kinds (visits stack))
  in
  match selection with
  | Known [] -> Format.pp_print_string fmt "none"
  | Known list -> Pretty_utils.pp_list ~sep:" " pretty fmt (List.map fst list)
  | Unknown_state [] -> Format.pp_print_string fmt "unknown"
  | Unknown_state stacks ->
    Format.fprintf fmt "unknown, reached on %a"
      (Pretty_utils.pp_list ~sep:" " pretty) stacks

let resolve_selection ?callstacks ~filter point f =
  if not (usable ()) then None
  else
    let log = !current in
    let supplied = Option.is_some callstacks in
    let stacks = selected_stacks log ?callstacks ~filter point in
    match selection_on log ~supplied stacks point with
    | exception Decline -> None
    | selection ->
      Legacy_read_guard.resolved
        (Domain_store.pretty_read_point point) (pretty_selection selection);
      Some (f log selection)

let select ?callstacks ~filter point =
  resolve_selection ?callstacks ~filter point (fun _ selection -> selection)

let all _ = true

(* The legacy answer on all callstacks. *)
let by_callstack = function
  | Unknown_state _ -> `Top
  | Known [] -> `Bottom
  | Known list -> `Value list

let resolve_by_callstack point =
  resolve_selection ~filter:all point (fun _ selection ->
      by_callstack selection)

(* Joins the states of all callstacks as the legacy consolidation does:
   in the order of the store, each new state on the left. *)
let consolidate = function
  | Unknown_state _ -> `Top
  | Known list ->
    let join acc (_, state) =
      match acc with
      | `Bottom -> `Value state
      | `Value acc -> `Value (Cvalue_domain.State.join state acc)
    in
    (List.fold_left join `Bottom list :> state Lattice_bounds.or_top_bottom)

(* The answers are final once the analysis has ended. *)
let resolve_consolidated point =
  resolve_selection ~filter:all point (fun log selection ->
      if log.completion = Recording then consolidate selection
      else memo log.consolidated point (fun () -> consolidate selection))

(* ----- Registration ------------------------------------------------------- *)

(* Eva still writes its legacy tables during the analysis: the requests that
   the resolver declines read them, and a saved project keeps them. Each
   write merges a new fact with the one already registered. While the hit
   log records, the facts already registered come from the records, and
   the legacy tables are only written. *)

let pretty_count what n fmt = Format.fprintf fmt "%d %s" n what

let registered ~callstack (point : Domain_store.control_point) =
  if not (recording ()) then None
  else
    let log = !current in
    let at_point (points : points) stmt =
      let table =
        match point with Before _ -> points.before | _ -> points.after
      in
      Stmt.Hashtbl.find_opt table stmt
    in
    (* The states that the earlier visits on [callstack] registered at
       [point]: their inputs at the start of the function, the states of
       their bodies at a statement. The registering invocation is the
       latest one; it is not recorded yet at the start of the function, and
       has no producer yet at a statement. *)
    let earlier =
      if not log.states then []
      else
        match point with
        | Initial -> []
        | Start kf ->
          List.map (fun v -> v.input) (visits_of kf callstack)
        | Before stmt | After stmt ->
          let kf = Kernel_function.find_englobing_kf stmt in
          let state visit =
            match visit.kind with
            | Body id ->
              begin match Hashtbl.find_opt log.producers id with
                | Some { points = Some points; _ } -> at_point points stmt
                | Some { points = None; _ } | None -> None
              end
            | Hit _ | Spec | Builtin _ | Unresolved -> None
          in
          List.filter_map state (visits_of kf callstack)
    in
    Legacy_read_guard.resolved
      (Domain_store.pretty_read_point ~callstack point)
      (pretty_count "earlier registrations" (List.length earlier));
    match earlier with
    | [] -> Some None
    | first :: others ->
      Some (Some (List.fold_left Cvalue_domain.State.join first others))

let target callstack status =
  if not (recording ()) then None
  else
    let log = !current in
    let kf = Callstack.top_kf callstack in
    let merged =
      match Kernel_function.Hashtbl.find_opt log.statuses kf with
      | None -> status
      | Some previous -> Function_calls.merge_status previous status
    in
    Kernel_function.Hashtbl.replace log.statuses kf merged;
    let previous =
      Kernel_function.Hashtbl.find_opt log.callers kf
      |> Option.value ~default:Kernel_function.Map.empty
    in
    let callers =
      match Callstack.top_caller callstack with
      | None -> previous
      | Some (stmt, caller) ->
        let stmts =
          Kernel_function.Map.find_opt caller previous
          |> Option.value ~default:Stmt.Set.empty
        in
        Kernel_function.Map.add caller (Stmt.Set.add stmt stmts) previous
    in
    Kernel_function.Hashtbl.replace log.callers kf callers;
    Legacy_read_guard.resolved
      (fun fmt ->
         Format.fprintf fmt "target of %a" Domain_store.pretty_callstack
           callstack)
      (fun fmt -> Format.pp_print_string fmt
          "analysis status and callers of the function");
    Some (merged, callers)

let () = Function_calls.set_recorded_target target

let fire stmt (then_, else_) =
  if not (recording ()) then None
  else
    let log = !current in
    let fired_then, fired_else =
      Stmt.Hashtbl.find_opt log.fired stmt
      |> Option.value ~default:(false, false)
    in
    let fired = fired_then || then_, fired_else || else_ in
    Stmt.Hashtbl.replace log.fired stmt fired;
    Legacy_read_guard.resolved
      (fun fmt -> Format.fprintf fmt "guard at line %d"
          (Fileloc.line (Cil_datatype.Stmt.loc stmt)))
      (fun fmt -> Format.pp_print_string fmt "fireable branches");
    Some fired

(* ----- Guard outcomes ---------------------------------------------------- *)

let condition_truth_value stmt =
  let log = !current in
  if not (usable ()) || log.has_hit || log.completion = Recording then None
  else
    let kf = Kernel_function.find_englobing_kf stmt in
    (* An unresolved invocation analyzed no body: an interrupted body
       records its producer. *)
    let add (then_, else_) invocation =
      match invocation.kind with
      | Body id ->
        let then', else' =
          match producer_of log kf id with
          | None -> false, false
          | Some producer ->
            Stmt.Hashtbl.find_opt producer.guards stmt
            |> Option.value ~default:(false, false)
        in
        then_ || then', else_ || else'
      | Hit _ | Spec | Builtin _ | Unresolved -> then_, else_
    in
    let invocations = List.rev (invocations_of log kf) in
    let answer = List.fold_left add (false, false) invocations in
    Legacy_read_guard.resolved
      (fun fmt -> Format.fprintf fmt "guard of %a at line %d"
          Kernel_function.pretty kf
          (Fileloc.line (Cil_datatype.Stmt.loc stmt)))
      (pretty_kinds invocations);
    Some answer

(* ----- Completion and analyzed functions -------------------------------- *)

(* The completion of the records, when they describe the current
   results. *)
let completion () =
  if not (usable ()) then None
  else
    let log = !current in
    Legacy_read_guard.resolved
      (fun fmt -> Format.pp_print_string fmt "computation state")
      (fun fmt -> Format.pp_print_string fmt
          (match log.completion with
           | Recording -> "recording"
           | Complete -> "complete"
           | Interrupted -> "interrupted"));
    Some log.completion

let computed () = Option.map (fun c -> c <> Recording) (completion ())

(* The records are started before the computation state becomes
   [Computing], and sealed or interrupted before it becomes [Computed] or
   [Aborted]: the hooks on these changes see the new completion. *)
let computation_state () =
  Option.map
    (function
      | Recording -> Self.Computing
      | Complete -> Self.Computed
      | Interrupted -> Self.Aborted)
    (completion ())

let analyzed kf =
  let log = !current in
  if not (usable ()) || log.completion <> Complete then None
  else
    let invocations = List.rev (invocations_of log kf) in
    let unresolved v = match v.kind with Unresolved -> true | _ -> false in
    if List.exists unresolved invocations then None
    else begin
      Legacy_read_guard.resolved
        (fun fmt -> Format.fprintf fmt "analysis of %a" Kernel_function.pretty kf)
        (pretty_kinds invocations);
      Some (List.exists (fun v -> match v.kind with
          | Body _ | Hit _ -> true
          | Spec | Builtin _ | Unresolved -> false) invocations)
    end

(* ----- Call relations ----------------------------------------------------- *)

(* The call relations of the invocations recorded so far: each invocation
   binds its function to its caller and its call statement, and the entry
   point to no caller. The legacy table registers a call when the analysis
   chooses how to interpret it, after the invocation is recorded and before
   any hook runs on it: at any time, both hold the same calls. *)
let compute_relations log =
  let add_call callers invocation =
    match Callstack.top_caller invocation.stack with
    | None -> callers
    | Some (stmt, caller) ->
      let stmts =
        Kernel_function.Map.find_opt caller callers
        |> Option.value ~default:Stmt.Set.empty
      in
      Kernel_function.Map.add caller (Stmt.Set.add stmt stmts) callers
  in
  let add kf invocations relations =
    let callers =
      List.fold_left add_call Kernel_function.Map.empty invocations
    in
    Kernel_function.Map.add kf callers relations
  in
  Kernel_function.Hashtbl.fold add log.by_kf Kernel_function.Map.empty

(* The calls below a memexec hit are not recorded: the relations decline
   once the records contain a hit. They are final once the analysis has
   ended. *)
let relations () =
  if not (usable ()) || (!current).has_hit then None
  else
    let log = !current in
    match log.completion, log.relations with
    | Recording, _ -> Some (compute_relations log)
    | (Complete | Interrupted), Some relations -> Some relations
    | (Complete | Interrupted), None ->
      let relations = compute_relations log in
      log.relations <- Some relations;
      Some relations

let () = Function_calls.set_recorded_relations relations

(* The analysis status of [kf] as the status table registers it. *)
let status kf =
  if not (usable ()) then None
  else
    let log = !current in
    let status =
      Kernel_function.Hashtbl.find_opt log.statuses kf
      |> Option.value ~default:Function_calls.Unreachable
    in
    Legacy_read_guard.resolved
      (fun fmt -> Format.fprintf fmt "analysis status of %a"
          Kernel_function.pretty kf)
      (fun fmt -> Format.pp_print_string fmt
          (match log.completion with
           | Recording -> "recording"
           | Complete -> "complete"
           | Interrupted -> "interrupted"));
    Some (status, log.completion <> Recording)

(* The calls below a memexec hit are not recorded: the answer declines once
   the records contain a hit. *)
let perturb_calls = ref false
let set_calls_perturbation_control b = perturb_calls := b

let calls () =
  let log = !current in
  if not (usable ()) || log.completion = Recording || log.has_hit then None
  else
    let to_map table =
      Kernel_function.Hashtbl.fold Kernel_function.Map.add table
        Kernel_function.Map.empty
    in
    let statuses = to_map log.statuses and relations = to_map log.callers in
    (* Test control: every function unreachable, without caller. *)
    let statuses, relations =
      if !perturb_calls then
        Kernel_function.Map.map (fun _ -> Function_calls.Unreachable) statuses,
        Kernel_function.Map.empty
      else statuses, relations
    in
    Legacy_read_guard.resolved
      (fun fmt -> Format.pp_print_string fmt "all functions")
      (fun fmt -> Format.pp_print_string fmt
          "analysis status and callers of each function");
    Some (Function_calls.make_results statuses relations)

(* ----- Snapshots -------------------------------------------------------- *)

(* The states of the callstacks that reach [point], as the legacy store
   records them. Where the records tell that the states are not recorded,
   the store records none. *)
let stored_states point =
  if not (usable ()) then None
  else
    let log = !current in
    match log.completion, function_level log point with
    | Recording, _ -> None
    | (Complete | Interrupted), Some (Pending | Interrupted) -> None
    | (Complete | Interrupted), Some Not_recorded ->
      Legacy_read_guard.resolved (Domain_store.pretty_read_point point)
        (fun fmt -> Format.pp_print_string fmt "not recorded");
      Some []
    | (Complete | Interrupted), None ->
      let stacks = selected_stacks log ~filter:all point in
      match selection_on log ~supplied:false stacks point with
      | exception Decline -> None
      | Unknown_state _ -> None
      | Known list as selection ->
        Legacy_read_guard.resolved (Domain_store.pretty_read_point point)
          (pretty_selection selection);
        Some list

type snapshot = log

let snapshot () =
  let log = !current in
  if usable () && log.completion <> Recording then Some log else None

(* The restored records get a stamp of their own: those of the analysis
   that produced them may still be current in another project. *)
let restore log =
  incr last_stamp;
  current := { log with stamp = !last_stamp };
  Current.set !last_stamp

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
