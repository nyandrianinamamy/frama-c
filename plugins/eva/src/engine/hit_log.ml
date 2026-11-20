(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Stmt = Cil_datatype.Stmt

type state = Cvalue_domain.State.t

type kind = Body of int | Hit of int | Spec_or_builtin

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
  entries: state list;
  points: points option;
}

(* The records of one analysis. They are plain tables shared by all
   projects; [Sealed] ties them to the results of one project. *)
type log = {
  stamp: int;
  exact: bool;
  mutable consistent: bool;
  mutable sealed: bool;
  mutable initial: (Callstack.t * state) option;
  invocations: invocation list Callstack.Hashtbl.t; (* latest first *)
  producers: (int, producer) Hashtbl.t;
  no_results: unit Kernel_function.Hashtbl.t;
  mutable open_calls: invocation list; (* innermost first *)
  mutable sequence: invocation list; (* all invocations, latest first *)
  (* Answers on all callstacks, computed once the records are sealed. *)
  by_callstack:
    (Callstack.t * state) list Lattice_bounds.or_top_bottom
      Domain_store.ControlPoint.Hashtbl.t;
  consolidated:
    state Lattice_bounds.or_top_bottom Domain_store.ControlPoint.Hashtbl.t;
}

let create stamp exact = {
  stamp; exact;
  consistent = true;
  sealed = false;
  initial = None;
  invocations = Callstack.Hashtbl.create 17;
  producers = Hashtbl.create 17;
  no_results = Kernel_function.Hashtbl.create 7;
  open_calls = [];
  sequence = [];
  by_callstack = Domain_store.ControlPoint.Hashtbl.create 17;
  consolidated = Domain_store.ControlPoint.Hashtbl.create 17;
}

let current = ref (create 0 false)
let last_stamp = ref 0

(* The stamp of the sealed records of the current results. It is cleared
   with the results of Eva and never saved: after a load, the records of
   the process do not describe the loaded results. *)
module Sealed =
  State_builder.Option_ref
    (Datatype.Int)
    (struct
      let name = "Eva.Hit_log.Sealed"
      let dependencies = [ Self.state ]
    end)

let () = Sealed.howto_marshal (fun _ -> None) ref

(* ----- Recording ---------------------------------------------------------- *)

let start ~exact =
  incr last_stamp;
  current := create !last_stamp exact

let seal () =
  let log = !current in
  if log.exact && log.consistent && log.open_calls = [] then begin
    log.sealed <- true;
    Sealed.set log.stamp
  end

let recording () =
  let log = !current in
  log.exact && not log.sealed

let initial stack state =
  if recording () then (!current).initial <- Some (stack, state)

let enter stack input =
  if recording () then
    let log = !current in
    let invocation = { stack; input; kind = Spec_or_builtin } in
    let visits =
      Option.value ~default:[] (Callstack.Hashtbl.find_opt log.invocations stack)
    in
    Callstack.Hashtbl.replace log.invocations stack (invocation :: visits);
    log.sequence <- invocation :: log.sequence;
    log.open_calls <- invocation :: log.open_calls

(* The innermost open invocation, which must be on [stack]. *)
let open_invocation stack =
  let log = !current in
  match log.open_calls with
  | invocation :: _ when Callstack.equal invocation.stack stack ->
    Some invocation
  | _ -> log.consistent <- false; None

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

let body stack ~producer ~entries ~points =
  if recording () then
    match open_invocation stack with
    | None -> ()
    | Some invocation ->
      let log = !current in
      let kf = Callstack.top_kf stack in
      let points = Option.map Lazy.force points in
      if Option.is_none points
      then Kernel_function.Hashtbl.replace log.no_results kf ();
      Hashtbl.replace log.producers producer { kf; entries; points };
      invocation.kind <- Body producer

(* ----- Resolver ----------------------------------------------------------- *)

let wrong_producer = ref false
let set_wrong_producer_control b = wrong_producer := b

let usable () =
  let log = !current in
  log.sealed && Sealed.get_option () = Some log.stamp

(* The visits on [stack], in the order of the analysis. *)
let visits stack =
  Callstack.Hashtbl.find_opt (!current).invocations stack
  |> Option.value ~default:[] |> List.rev

let is_hit invocation =
  match invocation.kind with
  | Hit _ -> true
  | Body _ | Spec_or_builtin -> false

(* A hit skips the body of the callee: nothing is recorded for the stacks
   below it. *)
let rec below_hit stack =
  match Callstack.pop stack with
  | None -> false
  | Some caller -> List.exists is_hit (visits caller) || below_hit caller

(* Joins in the order of the analysis, as the legacy store does. *)
let join_visits answers =
  let join acc answer =
    match acc, answer with
    | `Top, _ | _, `Top -> `Top
    | `Bottom, x | x, `Bottom -> x
    | `Value a, `Value b -> `Value (Cvalue_domain.State.join a b)
  in
  List.fold_left join `Bottom answers

(* The visits of [kf] on [stack]. *)
let visits_of kf stack =
  if Kernel_function.equal (Callstack.top_kf stack) kf then visits stack else []

(* The producer that rebuilds a body visit. *)
let producer_of log kf id =
  if !wrong_producer then
    let first id' producer acc =
      if Kernel_function.equal producer.kf kf && id' < fst acc
      then id', Some producer else acc
    in
    snd (Hashtbl.fold first log.producers (max_int, None))
  else Hashtbl.find_opt log.producers id

exception Decline

let rebuild_point log stack point stmt =
  let kf = Kernel_function.find_englobing_kf stmt in
  if Kernel_function.Hashtbl.mem log.no_results kf then `Top, []
  else if below_hit stack then raise Decline
  else
    let visits = visits_of kf stack in
    let table points =
      match point with
      | Domain_store.Before _ -> points.before
      | _ -> points.after
    in
    let rebuild invocation =
      match invocation.kind with
      | Hit _ -> raise Decline
      | Spec_or_builtin -> `Bottom
      | Body id ->
        match producer_of log kf id with
        | None -> raise Decline
        | Some { points = None; _ } -> `Top
        | Some { points = Some points; _ } ->
          match Stmt.Hashtbl.find_opt (table points) stmt with
          | Some state -> `Value state
          | None -> `Bottom
    in
    join_visits (List.map rebuild visits), visits

let rebuild stack (point : Domain_store.control_point) =
  let log = !current in
  match point with
  | Initial ->
    let answer =
      match log.initial with
      | Some (stack', state) when Callstack.equal stack stack' -> `Value state
      | _ -> `Bottom
    in
    answer, []
  | Start kf ->
    if below_hit stack then raise Decline;
    let visits = visits_of kf stack in
    join_visits (List.map (fun v -> `Value v.input) visits), visits
  | Before stmt | After stmt -> rebuild_point log stack point stmt

let pretty_kind fmt = function
  | Body id -> Format.fprintf fmt "body#%d" id
  | Hit id -> Format.fprintf fmt "hit#%d" id
  | Spec_or_builtin -> Format.pp_print_string fmt "spec-or-builtin"

let pretty_kinds visits fmt =
  match visits with
  | [] -> Format.pp_print_string fmt "none"
  | _ ->
    Pretty_utils.pp_list ~sep:"," pretty_kind fmt
      (List.map (fun v -> v.kind) visits)

let resolve ~callstack point =
  if not (usable ()) then None
  else
    match rebuild callstack point with
    | exception Decline -> None
    | answer, visits ->
      Legacy_read_guard.resolved
        (Domain_store.pretty_read_point ~callstack point)
        (pretty_kinds visits);
      Some answer

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
  match point with
  | Initial -> Option.to_list (Option.map fst log.initial)
  | Start kf ->
    List.rev log.sequence
    |> List.filter (fun v ->
        Kernel_function.equal (Callstack.top_kf v.stack) kf)
    |> List.map (fun v -> v.stack)
    |> first_occurrences
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
          | Body id when Kernel_function.equal (Callstack.top_kf v.stack) kf
                      && reaches id -> Some (id, v.stack)
          | Body _ | Hit _ | Spec_or_builtin -> None)
        log.sequence
    in
    List.sort (fun (a, _) (b, _) -> Int.compare a b) bodies
    |> List.map snd |> first_occurrences

(* The state at [point] on each callstack that reaches it, each rebuilt as
   by [rebuild], in the order of the legacy store; [`Bottom] if no
   callstack reaches it, [`Top] if the results of its function are not
   recorded. Declines when the records contain a memexec hit: the
   callstacks below a hit, and its points, are not recorded yet. *)
let rebuild_by_callstack log (point : Domain_store.control_point) =
  if List.exists is_hit log.sequence then raise Decline;
  let no_results =
    match point with
    | Initial | Start _ -> false
    | Before stmt | After stmt ->
      Kernel_function.Hashtbl.mem log.no_results
        (Kernel_function.find_englobing_kf stmt)
  in
  if no_results then `Top
  else
    let answer stack =
      match fst (rebuild stack point) with
      | `Value state -> Some (stack, state)
      | `Bottom -> None
      | `Top -> raise Decline
    in
    match List.filter_map answer (store_order (registrations log point)) with
    | [] -> `Bottom
    | list -> `Value list

(* Joins the states of all callstacks as the legacy consolidation does:
   in the order of the store, each new state on the left. *)
let consolidate = function
  | `Top -> `Top
  | `Bottom -> `Bottom
  | `Value list ->
    let join acc (_, state) =
      match acc with
      | `Bottom -> `Value state
      | `Value acc -> `Value (Cvalue_domain.State.join state acc)
    in
    (List.fold_left join `Bottom list :> state Lattice_bounds.or_top_bottom)

let memo table point compute =
  match Domain_store.ControlPoint.Hashtbl.find_opt table point with
  | Some answer -> answer
  | None ->
    let answer = compute () in
    Domain_store.ControlPoint.Hashtbl.replace table point answer;
    answer

let by_callstack log point =
  memo log.by_callstack point (fun () -> rebuild_by_callstack log point)

(* The callstacks of an answer and the kinds of their visits. *)
let pretty_stacks answer fmt =
  match answer with
  | `Top -> Format.pp_print_string fmt "top"
  | `Bottom -> Format.pp_print_string fmt "none"
  | `Value list ->
    let pretty fmt (stack, _) =
      Format.fprintf fmt "%a:%t" Domain_store.pretty_callstack stack
        (pretty_kinds (visits stack))
    in
    Pretty_utils.pp_list ~sep:" " pretty fmt list

let resolve_all point f =
  if not (usable ()) then None
  else
    let log = !current in
    match by_callstack log point with
    | exception Decline -> None
    | answer ->
      Legacy_read_guard.resolved
        (Domain_store.pretty_read_point point) (pretty_stacks answer);
      Some (f log answer)

let resolve_by_callstack point = resolve_all point (fun _ answer -> answer)

let resolve_consolidated point =
  resolve_all point (fun log answer ->
      memo log.consolidated point (fun () -> consolidate answer))

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
      | Hit _ | Spec_or_builtin -> "no body analysis"
    in
    Format.fprintf fmt "@[<v 2>%a: %s; input:@ %a@]"
      pretty_kind invocation.kind entries
      Cvalue.Model.pretty (fst invocation.input)
  in
  Pretty_utils.pp_list ~sep:"@\n" pretty_visit fmt (visits stack)
