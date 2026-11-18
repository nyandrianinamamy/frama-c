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

  (* ----- Cache of calls --------------------------------------------------- *)

  module Cache = Call_cache.Make (Engine.Val) (Engine.Dom)

  let collector_domain_supported =
    match Engine.Dom.structure with
    | Abstract.Domain.Leaf (key, _) ->
      Structure.Key_Domain.equal key Cvalue_domain.State.key
    | _ -> false

  (* Interprets a [call] in the state [init_state] by [compute], which analyzes
     the body of the called function, unless the cache has a matching entry. *)
  let compute_and_cache_call ~recursive ~save_results compute call init_state =
    (* The operations of the cache are outside the caller's analysis. *)
    let lookup () = Cache.lookup call init_state in
    match Body_access.without_recording lookup with
    | Cache.No_candidate pending ->
      let call_result, footprint =
        try
          Body_access.capture call.callstack (fun () ->
              if Body_access.is_recording () then begin
                begin match Callstack.top_callsite call.callstack with
                  | Kstmt { skind = Instr (Call (_, Mem _, _, _)); _ } ->
                    Body_access.refuse Indirect_call
                  | _ -> ()
                end;
                if recursive || not collector_domain_supported
                   || Mt_options.Enabled.get ()
                   || call.callstack.thread <> Thread.main_id
                then Body_access.unknown_access Side_table
              end;
              let result = compute call init_state in
              if Body_access.is_recording () && collector_domain_supported
              then begin
                let cvalue (_, state) = Engine.Dom.get_cvalue_or_top state in
                let exits = List.map cvalue result.Engine_sig.states in
                let entry = Engine.Dom.get_cvalue_or_top init_state in
                Body_access.check_written ~entry ~exits
              end;
              (* The caller frees the automatic blocks of the call when the
                 call returns. The release runs after the observation of the
                 body: the refusal is a prediction of it. The entry point
                 has no caller. *)
              let has_caller =
                match Callstack.top_callsite call.callstack with
                | Kstmt _ -> true
                | Kglobal -> false
              in
              if Body_access.is_recording ()
              && result.Engine_sig.states <> [] && has_caller
              && Builtins_malloc.deallocates_at_return call.callstack
              then Body_access.refuse Deallocation;
              result)
        with exn ->
          let backtrace = Printexc.get_raw_backtrace () in
          Cache.interrupted call pending;
          Printexc.raise_with_backtrace exn backtrace
      in
      Body_access.without_recording (fun () ->
          Cache.store ~save_results call init_state pending call_result
            footprint);
      call_result
    | Cache.Hit (i, states) ->
      apply_call_hooks call init_state `Reuse;
      (* Evaluate the preconditions of kf, to update the statuses
         at this call. *)
      Populate_spec.populate_funspec call.kf [`Assigns];
      let spec = Annotations.funspec call.kf in
      if not (Eva_utils.skip_specifications call.kf) &&
         List.exists (fun b -> b.b_requires <> []) spec.spec_behavior
      then begin
        let ab = Logic.create init_state call.kf in
        let kinstr = Callstack.top_callsite call.callstack in
        ignore (Logic.check_fct_preconditions kinstr call.kf ab init_state);
      end;
      Self.feedback ~current:true ~mkey:Log_key.progress
        "Reusing old results for call to %a" Kernel_function.pretty call.kf;
      apply_call_results_hooks call init_state (`Reuse i);
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
      apply_call_results_hooks call state (`Builtin ([], None));
      Engine_sig.{ states; cacheable = Cacheable; kind = `Builtin }
    | `Value final_state ->
      let cvalue_call = get_cvalue_call call in
      let post = Engine.Dom.get_cvalue_or_top final_state in
      let pre = Engine.Dom.get_cvalue_or_top state in
      Statistics.(incr (builtin_applied name) call.kf);
      let cvalue_states, cacheable =
        Builtins.apply_builtin builtin cvalue_call ~pre ~post
      in
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
  let compute_call_with_target ~recursive call target state =
    Function_calls.register_analysis_target call target;
    match target with
    | `Builtin builtin_info ->
      Body_access.unknown_access Builtin;
      compute_builtin builtin_info call state
    | `Spec _ as spec ->
      Body_access.unknown_access Contract;
      compute_using_spec_or_body spec call state
    | `Body (_, save_results) as def ->
      let compute = compute_using_spec_or_body def in
      compute_and_cache_call ~recursive ~save_results compute call state

  (* Defines the target of the analysis of a call, and analyze it.
     Exported in [Engine_sig.Compute] and used by [Transfer_stmt] when
     interpreting a call statement. *)
  let compute_call call recursion =
    with_callstack call.callstack @@ fun state ->
    let kf = call.kf in
    let callsite = Callstack.top_callsite call.callstack in
    let recursion_depth = Option.map (fun r -> r.depth) recursion in
    let target = Function_calls.analysis_target ?recursion_depth kf callsite in
    compute_call_with_target ~recursive:(Option.is_some recursion)
      call target state

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
