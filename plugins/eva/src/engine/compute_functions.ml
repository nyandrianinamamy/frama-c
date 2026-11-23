(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types
open Eval

module Make (Engine: Engine_sig.S) = struct

  module Logic = Engine.Transfer_logic
  module Spec = Engine.Transfer_specification

  type state = Engine.Dom.t
  type loc = Engine.Loc.location
  type value = Engine.Val.t

  let get_cval =
    match Engine.Val.get Main_values.CVal.key with
    | None -> fun _ -> assert false
    | Some get -> fun value -> get value

  let get_ploc =
    match Engine.Loc.get Main_locations.PLoc.key with
    | None -> fun _ -> assert false
    | Some get -> fun location -> get location

  let apply_call_hooks call state =
    let cvalue_state = Engine.Dom.get_cvalue_or_top state in
    Cvalue_callbacks.apply_call_hooks call.callstack call.kf cvalue_state

  let apply_call_results_hooks call state =
    let cvalue_state = Engine.Dom.get_cvalue_or_top state in
    Cvalue_callbacks.apply_call_results_hooks call.callstack call.kf cvalue_state

  (* ----- Mem Exec cache --------------------------------------------------- *)

  (* With -eva-hit-log, a call is stored and matched with the snapshot of
     the allocated blocks it mentions, see [Mem_exec]. *)
  module MemExec = Mem_exec.Make (Engine.Val) (Engine.Dom)

  (* With -eva-hit-log, the heap calls that memexec would store, see
     [Hit_log]. They are never reused: they only tell which calls memexec
     would have reused if it stored them, with the matching of memexec
     without the snapshot. *)
  module Refused = Mem_exec.Make (Engine.Val) (Engine.Dom)

  let compute_and_cache_call compute call init_state =
    let args =
      List.map (fun {avalue} -> Eval.value_assigned avalue) call.arguments
    in
    let record = Hit_log.enabled () in
    (* With -eva-hit-log, the actual arguments beyond the formals are
       arguments of the call for memexec: it compares their values, and the
       snapshot takes the blocks they point to. A call has such arguments
       through a pointer to a function type with more parameters, or to a
       variadic function under -no-variadic-translation. *)
    let memexec_args =
      if record && call.rest <> []
      then
        args @ List.map (fun (_, value) -> Eval.value_assigned value) call.rest
      else args
    in
    match
      MemExec.reuse_previous_call ~snapshot:record
        call.kf init_state memexec_args
    with
    | None ->
      let compute () = compute call init_state in
      let call_result =
        if record && Refused.has_previous_call call.kf init_state args
        then Hit_log.lost_hit call.kf compute
        else compute ()
      in
      let () =
        if call_result.Engine_sig.cacheable = Eval.Cacheable
        then
          let final_states = call_result.states in
          if record && Hit_log.heap_call ()
          then
            Refused.store_computed_call ~snapshot:false
              call.kf init_state args final_states
          else
            MemExec.store_computed_call ~snapshot:record
              call.kf init_state memexec_args final_states
      in
      call_result
    | Some (states, i) ->
      apply_call_hooks call init_state `Reuse;
      (* Evaluate the preconditions of kf, to update the statuses
         at this call. *)
      Populate_spec.populate_funspec call.kf [`Assigns];
      let spec = Annotations.funspec call.kf in
      let body_entry_states =
        if not (Eva_utils.skip_specifications call.kf) &&
           List.exists (fun b -> b.b_requires <> []) spec.spec_behavior
        then begin
          let ab = Logic.create init_state call.kf in
          let kinstr = Callstack.top_callsite call.callstack in
          Logic.check_fct_preconditions kinstr call.kf ab init_state
        end
        else [ init_state ]
      in
      if record then begin
        let start = Engine.Dom.get_cvalue_or_top init_state in
        let body_entry =
          match Bottom.List.join Engine.Dom.join body_entry_states with
          | `Bottom -> Cvalue.Model.bottom
          | `Value state -> Engine.Dom.get_cvalue_or_top state
        in
        Hit_log.record_hit ~id:i call.callstack ~start ~body_entry
      end;
      Self.feedback ~current:true ~mkey:Log_key.progress
        "Reusing old results for call to %a" Kernel_function.pretty call.kf;
      let substitution = Base.substitution_from_list [] in
      apply_call_results_hooks call init_state (`Reuse (i, substitution));
      (* call can be cached since it was cached once *)
      Engine_sig.{ states; cacheable = Cacheable; kind = `Body }

  (* ----- Body or specification analysis ----------------------------------- *)

  (* Interprets a [call] in the state [state] by analyzing
     the body of the called function. *)
  let compute_using_body ~save_results call state =
    Engine.Iterator.compute ~save_results call.callstack state

  (* Interprets a [call] at callsite [kinstr] in the state [state] by using the
     specification of the called function. *)
  let compute_using_spec spec call state =
    if Parameters.InterpreterMode.get ()
    then Self.abort "Library function call. Stopping.";
    let vi = Kernel_function.get_vi call.kf in
    (* Use vorig_name to avoid message duplication due to variadic renaming. *)
    Self.feedback ~level:3 ~once:true
      "@[using specification for function %a@]"
      Printer.pp_varname vi.vorig_name;
    if Cil.is_in_libc vi.vattr then
      Library_functions.warn_unsupported_spec vi.vorig_name;
    let states =
      Spec.compute_using_specification ~warn:true call spec state
    in
    let get_cvalue (_key, state) = Engine.Dom.get_cvalue_or_top state in
    let cvalue_states = List.map get_cvalue states in
    apply_call_results_hooks call state (`Spec cvalue_states);
    states, Eval.Cacheable

  (* Interprets a [call] in state [state], using its
     specification or body according to [target]. If [-eva-show-progress] is
     true, the callstack and additional information are printed. *)
  let compute_using_spec_or_body target call state =
    let pos = Eval.position_of_call call in
    if Position.is_local pos then
      Self.feedback ~mkey:Log_key.progress
        "@[computing for function %a.@\nCalled from %a.@]"
        Callstack.pretty_short call.callstack
        Position.pretty_loc pos;
    let compute, kind =
      match target with
      | `Body (_, save_results) -> compute_using_body ~save_results, `Body
      | `Spec funspec -> compute_using_spec funspec, `Spec
    in
    apply_call_hooks call state kind;
    let resulting_states, cacheable = compute call state in
    Self.feedback ~mkey:Log_key.progress
      "Done for function %a" Kernel_function.pretty call.kf;
    Engine_sig.{ states = resulting_states; cacheable; kind }

  (* ----- Use of cvalue builtins ------------------------------------------- *)

  let get_cvalue_call call =
    let lift_left left = { left with lloc = get_ploc left.lloc } in
    let lift_flagged_value value = { value with v = value.v >>-: get_cval } in
    let lift_assigned = function
      | Assign value -> Assign (get_cval value)
      | Copy (lval, value) -> Copy (lift_left lval, lift_flagged_value value)
    in
    let lift_argument arg = { arg with avalue = lift_assigned arg.avalue } in
    let arguments = List.map lift_argument call.arguments in
    let rest = List.map (fun (e, assgn) -> e, lift_assigned assgn) call.rest in
    { call with arguments; rest }

  (* Interprets a call to [kf] at callsite [kinstr] in the state [state]
     by using a cvalue builtin. *)
  let compute_builtin (name, builtin, spec) call state =
    let kf_name = Kernel_function.get_name call.kf in
    Self.feedback ~current:true ~mkey:Log_key.progress
      "Call to builtin %s%s"
      name (if kf_name = name then "" else " for function " ^ kf_name);
    apply_call_hooks call state `Builtin;
    let states =
      Spec.compute_using_specification ~warn:false call spec state
    in
    let final_state = Bottom.List.join Engine.Dom.join (List.map snd states) in
    match final_state with
    | `Bottom ->
      if Hit_log.enabled () then Hit_log.builtin_outputs 0;
      apply_call_results_hooks call state (`Builtin ([], None));
      Engine_sig.{ states; cacheable = Cacheable; kind = `Builtin }
    | `Value final_state ->
      let cvalue_call = get_cvalue_call call in
      let post = Engine.Dom.get_cvalue_or_top final_state in
      let pre = Engine.Dom.get_cvalue_or_top state in
      let cvalue_states, cacheable =
        Builtins.apply_builtin builtin cvalue_call ~pre ~post
      in
      if Hit_log.enabled ()
      then Hit_log.builtin_outputs (List.length cvalue_states);
      let insert rank cvalue_state =
        let kinstr = Callstack.top_callsite call.callstack in
        let branch = Partition.Builtin_result { kf=call.kf; kinstr; rank } in
        Partition.Key.(add_branch branch empty),
        Engine.Dom.set Cvalue_domain.State.key cvalue_state final_state
      in
      let states = List.mapi insert cvalue_states in
      Engine_sig.{ states; cacheable; kind = `Builtin }

  (* Uses cvalue builtin only if the cvalue domain is available. Otherwise, only
     use the called function specification. *)
  let compute_builtin =
    if Engine.Dom.mem Cvalue_domain.State.key
    && Engine.Val.mem Main_values.CVal.key
    && Engine.Loc.mem Main_locations.PLoc.key
    then compute_builtin
    else fun (_, _, spec) -> compute_using_spec_or_body (`Spec spec)

  (* ----- Call computation ------------------------------------------------- *)

  (* Execute the function [job] with the current callstack set to [callstack],
     and update [Eva_perf] accordingly *)
  let with_callstack callstack job x =
    Eva_perf.start callstack;
    let finally () = Eva_perf.stop callstack in
    Current_callstack.with_callstack ~finally callstack job x

  (* Interprets a [call] in the state [state], using a builtin, specification or
     the body of the called function according to [target]. *)
  let compute_call_with_target call target state =
    Function_calls.register_analysis_target call target;
    let record = Hit_log.enabled () in
    let start = lazy (Engine.Dom.get_cvalue_or_top state) in
    let record_start () =
      if record then Hit_log.record_start call.callstack (Lazy.force start)
    in
    let compute () =
      match target with
      | `Builtin builtin_info ->
        record_start ();
        compute_builtin builtin_info call state
      | `Spec _ as spec ->
        record_start ();
        compute_using_spec_or_body spec call state
      | `Body _ as def ->
        let compute = compute_using_spec_or_body def in
        if Parameters.Memexec.get ()
        then compute_and_cache_call compute call state
        else compute call state
    in
    if record
    then Hit_log.call call.callstack ~start:(Lazy.force start) compute
    else compute ()

  (* Defines the target of the analysis of a call, and analyze it.
     Exported in [Engine_sig.Compute] and used by [Transfer_stmt] when
     interpreting a call statement. *)
  let compute_call call recursion =
    with_callstack call.callstack @@ fun state ->
    let kf = call.kf in
    let callsite = Callstack.top_callsite call.callstack in
    let recursion_depth = Option.map (fun r -> r.depth) recursion in
    let target = Function_calls.analysis_target ?recursion_depth kf callsite in
    begin match target, recursion with
      | `Body _, Some _ when Hit_log.enabled () ->
        Hit_log.mark_unrolled_recursion kf
      | _ -> ()
    end;
    Option.iter (Hit_log.recursive_call call.callstack) recursion;
    compute_call_with_target call target state

  (* ----- Main call -------------------------------------------------------- *)

  (* Abort if the main function is interpreted by a builtin. *)
  let check_main_function_target kf = function
    | `Builtin _ ->
      Self.abort
        "Cannot analyze program from main function %a, for which a builtin is used."
        Kernel_function.pretty kf
    | `Spec _ | `Body _ -> ()

  let compute_main_call ~thread kf init_state =

    let compute_call_and_join =
      let thread_id = Thread.id thread in
      let callstack = Callstack.init ~thread:thread_id ~entry_point:kf in
      Current_callstack.with_callstack callstack @@ fun init_state ->
      Engine.Dom.Store.register_state callstack (Start kf) init_state;
      let init_state =
        (* Inject interferences in the initial state. The interferences are
           injected after registering the initial state as this is part of the
           analysis. *)
        Engine.Interferences.inject_init_state thread kf init_state
      in
      let call = { kf; callstack; arguments = []; rest = []; return = None; } in
      check_main_function_target kf (Function_calls.analysis_target kf Kglobal);
      let final_result = compute_call call None init_state in
      let final_states = List.map snd (final_result.states) in
      let final_state = Bottom.List.join Engine.Dom.join final_states in
      final_state
    in

    if Thread.is_interrupt_handler kf then
      (* If the function is an interrupt handler, then it can be called several
         times. As a result we need to find a fixpoint. *)
      let widening_delay = Parameters.WideningDelay.get () in
      let widening_period = Parameters.WideningPeriod.get () in

      let widen_state counter previous current =
        let current = Engine.Dom.join previous current in
        let counter, next =
          if counter > 0 then
            (* No widening *)
            counter, current
          else
            let widened =
              Engine.Dom.widen kf Cil_datatype.Stmt.dummy previous current
            in
            widening_period, widened
        in
        counter - 1, next
      in

      let rec aux i widening_counter previous =
        let open Eval.Bottom.Operators in
        let* current = compute_call_and_join previous in
        if Engine.Dom.is_included current previous then
          `Value previous
        else
          let widening_counter, next =
            widen_state widening_counter previous current
          in
          aux (i + 1) widening_counter next
      in

      aux 1 (widening_delay - 1) init_state
    else
      (* Otherwise just compute the call normally. *)
      compute_call_and_join init_state
end
