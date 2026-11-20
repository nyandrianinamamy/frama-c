(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* Throwaway state-query experiment. Enabled by the prototype runner only. *)

open Cil_types

module M = Cvalue.Model
module Zone = Memory_zone
module Bits = Int_Intervals
module O = Cvalue.V_Offsetmap
module R = Eva.Results

module Phase = Inout_parameters.QueryPrototype

type prefix = {
  reads : Zone.t;
  may_write : Zone.t;
  sure_write : Zone.t;
}

type slice = {
  base : Base.t;
  first : Z.t;
  last : Z.t;
  payload : O.t option;
}

type alternative = {
  predecessor : stmt;
  slices : slice list;
}

type projected =
  | Remove of Base.t
  | Install of Base.t * O.t
  | Retain of { slice : slice; may_pass_through : bool }

type projection = Unreachable | Unavailable | Reachable of projected list

type point = {
  state : M.t;
  prefix : prefix option;
  alternatives : alternative list;
  earlier : (stmt * alternative list) option;
  projected : projection;
  write_only : projection;
}

type producer = {
  entry : M.t;
  before : point;
  after : point;
}

type invocation = {
  stack : Eva.Callstack.t;
  entry : M.t;
  kind : [ `Body of int | `Reuse of int ];
}

let producers = Hashtbl.create 7
let invocations = ref []

let log fmt = Format.printf ("[query] " ^^ fmt ^^ "@.")

let is_label name = function Label (s, _, _) -> s = name | _ -> false

let target kf =
  if Kernel_function.is_definition kf then
    let body = Kernel_function.get_definition kf in
    List.find_opt (fun s -> List.exists (is_label "P") s.labels) body.sallstmts
  else None

let selected kf = Phase.get () <> "" && Option.is_some (target kf)

let from_table table stmt =
  Option.value ~default:M.bottom
    (Cil_datatype.Stmt.Hashtbl.find_opt (Lazy.force table) stmt)

let join_effect x y = {
  reads = Zone.join x.reads y.reads;
  may_write = Zone.join x.may_write y.may_write;
  sure_write = Zone.meet x.sure_write y.sure_write;
}

let maybe_only { reads; may_write; sure_write } =
  Zone.diff may_write (Zone.join reads sure_write)

let address base first = Addresses.Bits.inject base (Ival.inject_singleton first)
let size first last = Z.succ (Z.sub last first)

let extract state base first last =
  match M.copy_offsetmap (address base first) (size first last) state with
  | `Value payload -> payload
  | `Bottom -> raise Not_found

let paste state base first last payload =
  M.paste_offsetmap ~from:payload ~dst_addr:(address base first)
    ~size:(size first last) ~exact:true state

let fold_ranges f zone init =
  Zone.fold_i (fun base -> Bits.fold (fun (first, last) -> f base first last))
    zone init

let bases state =
  match state with
  | M.Map map ->
    M.fold (fun base _ acc -> Base.Hptset.add base acc) map Base.Hptset.empty
  | M.Bottom | M.Top -> raise Not_found

let get_explicit base state =
  match M.find_base base state with
  | `Value m -> Some m
  | `Bottom | `Top -> None
  | exception Not_found -> None

let same_offsetmap = Option.equal O.equal

let replace_base base binding state =
  match binding with
  | None -> M.remove_base base state
  | Some offsetmap -> M.add_base base offsetmap state

let project entry state prefix =
  let affected = Zone.join prefix.reads prefix.may_write in
  let uncertain = maybe_only prefix in
  let all_bases = Base.Hptset.union (bases state) (bases entry) in
  Base.Hptset.fold
    (fun base acc ->
       match get_explicit base entry, get_explicit base state with
       | None, None -> acc
       | Some _, None -> Remove base :: acc
       | None, Some offsetmap -> Install (base, offsetmap) :: acc
       | Some _, Some _ ->
         if not (Zone.mem_base base affected) then acc else
           let zone = Zone.filter_base (Base.equal base) in
           let retained = zone affected in
           let add may_pass_through =
             fold_ranges (fun base first last acc ->
                 let payload = Some (extract state base first last) in
                 Retain { slice = { base; first; last; payload };
                          may_pass_through } :: acc)
           in
           let maybe = zone uncertain in
           add true maybe (add false (Zone.diff retained maybe) acc))
    all_bases []

let assemble entry = function
  | Unreachable -> M.bottom
  | Unavailable -> M.top
  | Reachable projected ->
    List.fold_left
      (fun state -> function
         | Remove base -> M.remove_base base state
         | Install (base, offsetmap) -> M.add_base base offsetmap state
         | Retain { slice = { base; first; last; payload }; may_pass_through } ->
           let value = Option.get payload in
           let value =
             if may_pass_through then
               O.join value (extract entry base first last)
             else value
           in
           paste state base first last value)
      entry projected

let split_before stmt results state prefix edges =
  let zone = maybe_only prefix in
  if Zone.is_bottom zone then [] else
    let preds =
      List.filter_map
        (fun pred ->
           let before = from_table results.Eva.Cvalue_callbacks.before_stmts pred in
           if M.is_reachable before then
             let edge = List.find (fun (succ, _) -> succ == stmt) (edges pred) in
             let pred_state =
               match pred.skind with
               | Instr _ -> from_table results.Eva.Cvalue_callbacks.after_stmts pred
               | Goto (destination, _) when !destination == stmt -> before
               | If _ ->
                 (* For the direct fall-through edge, only retain parts that
                    were neither read by the guard nor modified on this path. *)
                 let _, effect = edge in
                 if Zone.intersects zone effect.reads then raise Not_found;
                 before
               | _ -> raise Not_found
             in
             Some (pred, pred_state, snd edge)
           else None)
        stmt.preds
    in
    let joined =
      List.fold_left (fun acc (_, s, _) -> M.join acc s) M.bottom preds
    in
    if List.length preds < 2 || not (M.equal joined state) then [] else
      List.map
        (fun (predecessor, edge_state, effect) ->
           let slices =
             fold_ranges (fun base first last acc ->
                 let part = Zone.inject base (Bits.inject_bounds first last) in
                 let payload =
                   if Zone.is_included part effect.sure_write then
                     Some (extract edge_state base first last)
                   else if Zone.intersects part (Zone.join effect.reads effect.may_write)
                   then raise Not_found
                   else None
                 in
                 { base; first; last; payload } :: acc)
               zone []
           in
           { predecessor; slices })
        preds

let one_step_earlier stmt results effect edges local_edges =
  let zone = maybe_only effect in
  if Zone.is_bottom zone then None else
    match stmt.preds with
    | [bridge] ->
      (match bridge.skind with
       | Instr (Set ((Var vi, NoOffset), exp, _))
         when vi.vglob
           && Ast_types.C.is_integral vi.vtype
           && not (Ast_types.C.is_volatile vi.vtype)
           && Option.is_some (Cil.isInteger exp) ->
         let local = local_edges bridge in
         (match local with
          | [(succ, footprint)] when succ == stmt
                                  && not (Zone.intersects zone (Zone.join footprint.reads footprint.may_write)) ->
            let state = from_table results.Eva.Cvalue_callbacks.before_stmts bridge in
            let alternatives = split_before bridge results state effect edges in
            if alternatives = [] then None else Some (bridge, alternatives)
          | _ -> None)
       | _ -> None)
    | _ -> None

let project_point entry state prefix =
  match prefix with
  | Some effect ->
    let writes = { effect with reads = Zone.bottom } in
    Reachable (project entry state effect), Reachable (project entry state writes)
  | None ->
    let missing = if M.is_reachable state then Unavailable else Unreachable in
    missing, missing

let body kf results id entry prefix edges local_edges =
  let stmt = Option.get (target kf) in
  let before = from_table results.Eva.Cvalue_callbacks.before_stmts stmt in
  let after = from_table results.Eva.Cvalue_callbacks.after_stmts stmt in
  let before =
    let prefix = if M.is_reachable before then Some (prefix stmt) else None in
    let projected, write_only = project_point entry before prefix in
    let alternatives, earlier =
      match prefix with
      | None -> [], None
      | Some effect ->
        (try
           let direct = split_before stmt results before effect edges in
           let earlier =
             if direct = [] then one_step_earlier stmt results effect edges local_edges
             else None
           in
           direct, earlier
         with Not_found | Abstract_interp.Error_Top -> [], None)
    in
    { state = before; prefix; alternatives; earlier; projected; write_only }
  in
  let after =
    let prefix =
      if M.is_reachable after then
        let after_edges = List.map snd (edges stmt) in
        match after_edges with
        | hd :: tl -> Some (List.fold_left join_effect hd tl)
        | [] -> None
      else None
    in
    let projected, write_only = project_point entry after prefix in
    { state = after; prefix; alternatives = []; earlier = None;
      projected; write_only }
  in
  Hashtbl.replace producers id { entry; before; after }

let record stack kf entry = function
  | `Body (_, id) when selected kf ->
    invocations := { stack; entry; kind = `Body id } :: !invocations
  | `Reuse id when selected kf ->
    invocations := { stack; entry; kind = `Reuse id } :: !invocations
  | _ -> ()

let () =
  Eva.Cvalue_callbacks.register_at_start_hook (fun () ->
      invocations := []; Hashtbl.clear producers)

let rebase_whole_base producer current point =
  let state = point.state in
  if not (M.is_reachable state) then state else
    let prefix = Option.get point.prefix in
    let affected = Zone.join prefix.reads prefix.may_write in
    let all_bases = Base.Hptset.union (bases producer) (bases current) in
    Base.Hptset.fold
      (fun base acc ->
         let old_entry = get_explicit base producer in
         let new_entry = get_explicit base current in
         if same_offsetmap old_entry new_entry then acc
         else if not (Zone.mem_base base affected) then
           replace_base base new_entry acc
         else
           match Base.validity base with
           | Base.Known (first, last) ->
             let full = Zone.inject base (Bits.inject_bounds first last) in
             if Zone.is_included full prefix.sure_write
             || Zone.mem_base base prefix.reads then acc
             else
               let merged = M.join state current in
               replace_base base (get_explicit base merged) acc
           | _ -> raise Not_found)
      all_bases state

let apply_alternatives current fallback alternatives =
  match alternatives with
  | [] -> fallback
  | _ ->
    List.fold_left
      (fun joined { slices; _ } ->
         let state =
           List.fold_left (fun state { base; first; last; payload } ->
               let payload =
                 match payload with
                 | Some value -> value
                 | None -> extract current base first last
               in
               paste state base first last payload)
             fallback slices
         in
         M.join joined state)
      M.bottom alternatives

let request point stmt =
  match point with "before" -> R.before stmt | _ -> R.after stmt

let stack_name stack =
  let entry = Kernel_function.get_name stack.Eva.Callstack.entry_point in
  let calls = Eva.Callstack.to_call_list stack in
  let parts =
    List.filter_map (fun (kf, kinstr) ->
        match kinstr with
        | Kglobal -> None
        | Kstmt stmt ->
          let loc = Cil_datatype.Stmt.loc stmt in
          Some (Printf.sprintf "%s@%d" (Kernel_function.get_name kf)
                  (Fileloc.line loc)))
      calls
  in
  String.concat "/" (entry :: parts)

let event_id = function
  | `Body id -> Printf.sprintf "Body/%d" id
  | `Reuse id -> Printf.sprintf "Reuse/%d" id

let status = function
  | Ok m when M.is_top m -> "value(top-model)"
  | Ok m when not (M.is_reachable m) -> "value(bottom-model)"
  | Ok _ -> "value"
  | Error R.Bottom -> "bottom"
  | Error R.Top -> "top"
  | Error R.DisabledDomain -> "disabled"

let classify expected observed =
  if M.equal expected observed then "EXACT"
  else if M.is_included expected observed then "CONTAINS_FRESH"
  else "OMITS_FRESH"

let pretty_model fmt state =
  Format.fprintf fmt "@[<v>%a@]" M.pretty state

let show label state = log "%s = %a" label pretty_model state

let legacy kf stmt point stack =
  let req = request point stmt in
  let req = Option.fold ~none:req ~some:(fun s -> R.in_callstack s req) stack in
  let result = R.get_cvalue_model_result req in
  log "%s legacy available=%b status=%s callstacks=%d"
    point (R.are_available kf) (status result) (List.length (R.callstacks req));
  R.get_cvalue_model req

let summarize label baseline state =
  log "%s %s" label (classify baseline state);
  show label state

let lookup id = Hashtbl.find_opt producers id

let print_prefix where p =
  match p.prefix with
  | None -> log "%s prefix unavailable" where
  | Some { reads; may_write; sure_write } ->
    log "%s prefix reads=%a may-write=%a sure-write=%a"
      where Zone.pretty reads Zone.pretty may_write Zone.pretty sure_write

let print_projection where p =
  match p.projected with
  | Unreachable | Unavailable -> ()
  | Reachable projected ->
    List.iter
      (function
        | Remove base -> log "%s projected remove %a" where Base.pretty base
        | Install (base, _) -> log "%s projected install %a" where Base.pretty base
        | Retain { slice = { base; first; last; _ }; may_pass_through } ->
          log "%s projected %a[%a..%a] %s" where Base.pretty base Z.pp_print first
            Z.pp_print last (if may_pass_through then "join" else "replace"))
      projected

let get_point point producer =
  if point = "before" then producer.before else producer.after

let strategies = ["producer"; "whole-base"; "write-only"; "bitwise"; "split"; "lookback"]

let for_invocation point { entry; kind; _ } =
  let id = match kind with `Body id | `Reuse id -> id in
  match lookup id with
  | None -> List.map (fun _ -> M.top) strategies
  | Some producer ->
    let p = get_point point producer in
    let bits = assemble entry p.projected in
    let split = apply_alternatives entry bits p.alternatives in
    let lookback =
      match p.earlier with
      | None -> split
      | Some (_, alternatives) -> apply_alternatives entry bits alternatives
    in
    let whole =
      match kind with
      | `Body _ -> p.state
      | `Reuse _ -> rebase_whole_base producer.entry entry p
    in
    [p.state; whole; assemble entry p.write_only; bits; split; lookback]

let show_alternatives where alternatives =
  List.iter
    (fun { predecessor; slices } ->
       let line = Fileloc.line (Cil_datatype.Stmt.loc predecessor) in
       List.iter
         (fun { base; first; last; payload } ->
            let mode =
              match payload with None -> "pass-through" | Some _ -> "write"
            in
            log "%s alternative predecessor=stmt%d@%d %a[%a..%a] %s"
              where predecessor.sid line Base.pretty base Z.pp_print first
              Z.pp_print last mode)
         slices)
    alternatives

let show_invocation n ({ stack; entry; kind } as call) =
  log "event %d stack=%s %s" n (stack_name stack) (event_id kind);
  show "entry" entry;
  let id = match kind with `Body id | `Reuse id -> id in
  match lookup id with
  | None -> log "point payload unavailable"
  | Some producer ->
    List.iter (fun where ->
        let p = get_point where producer in
        print_prefix where p;
        print_projection where p;
        let answers = List.combine strategies (for_invocation where call) in
        (match kind with
         | `Body _ ->
           log "%s body-frame reconstruction=%s" where
             (classify (List.assoc "producer" answers) (List.assoc "bitwise" answers))
         | `Reuse _ -> ());
        List.iter (fun (method_, result) -> show (where ^ " " ^ method_) result) answers;
        show_alternatives where p.alternatives;
        Option.iter
          (fun (bridge, alternatives) ->
             log "%s lookback across stmt%d" where bridge.sid;
             show_alternatives (where ^ " lookback") alternatives)
          p.earlier)
      ["before"; "after"]

let baseline = Hashtbl.create 13

let grouped point calls =
  let identity = List.map (fun _ -> M.bottom) strategies in
  let join acc call = List.map2 M.join acc (for_invocation point call) in
  List.combine strategies (List.fold_left join identity calls)

let summarize_query phase kf stmt stack calls =
  let name = Option.fold ~none:"joined" ~some:stack_name stack in
  List.iter (fun point ->
      log "query %s %s %s" phase name point;
      let normal = legacy kf stmt point stack in
      let key = name, point in
      let compare expected =
        List.iter (fun (method_, model) -> summarize method_ expected model)
          (grouped point calls)
      in
      match phase with
      | "fresh" ->
        Hashtbl.replace baseline key normal;
        show "fresh" normal;
        compare normal
      | "hit" ->
        let expected = Hashtbl.find baseline key in
        summarize "legacy" expected normal;
        compare expected
      | _ ->
        show "legacy" normal;
        log "prototype unavailable")
    ["before"; "after"]

let summarize_storage () =
  let projected, alternatives, stored_slices, references, bridges =
    Hashtbl.fold
      (fun _ producer acc ->
         let count (p, a, s, r, b) { alternatives; earlier; projected; _ } =
           let b, alternatives =
             match earlier with
             | None -> b, alternatives
             | Some (_, saved) -> b + 1, saved @ alternatives
           in
           let p =
             match projected with
             | Reachable projected -> p + List.length projected
             | Unreachable | Unavailable -> p
           in
           List.fold_left
             (fun (p, a, s, r, b) { slices; _ } ->
                let payloads =
                  List.length (List.filter
                                 (fun slice -> Option.is_some slice.payload)
                                 slices)
                in
                p, a + 1, s + payloads, r + List.length slices - payloads, b)
             (p, a, s, r, b) alternatives
         in
         count (count acc producer.before) producer.after)
      producers (0, 0, 0, 0, 0)
  in
  log "storage frames=%d producers=%d point-slots=%d projected-entries=%d"
    (List.length !invocations) (Hashtbl.length producers)
    (2 * Hashtbl.length producers) projected;
  log "storage extra-alternatives=%d extra-offsetmaps=%d extra-pass-through=%d"
    alternatives stored_slices references;
  log "storage lookback-edges=%d" bridges

let run () =
  let phase = Phase.get () in
  if phase <> "" then begin
    Eva.Parameters.Memexec.set (phase <> "fresh" && phase <> "missing");
    Project.clear ~selection:(State_selection.with_dependencies Eva.Analysis.self)
      ();
    Eva.Analysis.compute ();
    let kf, stmt = Globals.Functions.fold (fun kf found ->
        match target kf with Some stmt -> Some (kf, stmt) | None -> found)
        None |> Option.get
    in
    let calls = List.rev !invocations in
    log "phase %s memexec=%b target=%a statement=%d" phase
      (Eva.Parameters.Memexec.get ()) Kernel_function.pretty kf stmt.sid;
    List.iteri (fun i -> show_invocation (i + 1)) calls;
    let stacks =
      List.map (fun call -> call.stack) calls
      |> List.sort_uniq Eva.Callstack.compare
    in
    List.iter (fun stack ->
        let own = List.filter (fun call -> Eva.Callstack.equal call.stack stack)
            calls in
        summarize_query phase kf stmt (Some stack) own)
      stacks;
    summarize_query phase kf stmt None calls;
    summarize_storage ()
  end

let () = Boot.Main.extend run
