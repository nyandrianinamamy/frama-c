(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types
open Eval

type refusal = [
  | `Disabled
  | `Not_cacheable
  | `No_inout
  | `Footprint_top
  | `Relate_top
  | `Relate_unclosed
  | `Exception
  | `Supplied_only
]

let refusals : refusal list =
  [ `Disabled; `Not_cacheable; `No_inout; `Footprint_top; `Relate_top;
    `Relate_unclosed; `Exception; `Supplied_only ]

let refusal_id : refusal -> string = function
  | `Disabled -> "disabled"
  | `Not_cacheable -> "not-cacheable"
  | `No_inout -> "no-inout"
  | `Footprint_top -> "footprint-top"
  | `Relate_top -> "relate-top"
  | `Relate_unclosed -> "relate-unclosed"
  | `Exception -> "exception"
  | `Supplied_only -> "supplied-only"

(* No verbosity level: the category is enabled only by -eva-msg-key. *)
let mkey =
  let ids f l = String.concat ", " (List.map f l) in
  Self.register_message_category "cache"
    ~help:(Printf.sprintf
             "print the dispositions of each call analysed through the body \
              of the called function or answered by the cache of calls: \
              lookup in the cache (no-candidate, hit, or entries supplied by \
              a test module and rejected with one of the reasons: %s), \
              execution of the body (analysed, not-analysed or interrupted) \
              and storage of the result (stored, none, or refused with one of \
              the reasons: %s)"
             (ids Supplied_entries.rejection_id Supplied_entries.rejections)
             (ids refusal_id refusals))

let producer_mkey =
  Self.register_message_category "cache-producer"
    ~help:"show storage of entries produced from fresh bodies"

let new_counter = Mem_exec.new_counter

let cleanup_results () =
  Mem_exec.cleanup_results ();
  Cache_call_trace.clear ()

(* ----- Report of the dispositions of a call ------------------------------ *)

(* The candidates rejected, oldest first, then the entry used, if any. *)
type lookup_disposition = {
  rejected : (int * Supplied_entries.rejection) list;
  hit : int option;
}

let no_candidate = { rejected = []; hit = None }
type execution_disposition = [ `Analysed | `Not_analysed | `Interrupted ]
type storage_disposition = [ `None | `Stored of int | `Refused of refusal ]

let pretty_lookup fmt = function
  | { rejected = []; hit = None } ->
    Format.pp_print_string fmt "no-candidate"
  | { rejected; hit } ->
    let pretty_rejected fmt (id, reason) =
      Format.fprintf fmt "rejected (entry %d: %s)"
        id (Supplied_entries.rejection_id reason)
    in
    let pretty_hit fmt id = Format.fprintf fmt "hit (entry %d)" id in
    Pretty_utils.pp_list ~sep:", " pretty_rejected fmt rejected;
    if rejected <> [] && hit <> None then Format.pp_print_string fmt ", ";
    Pretty_utils.pp_opt pretty_hit fmt hit

let pretty_execution fmt (execution : execution_disposition) =
  Format.pp_print_string fmt
    (match execution with
     | `Analysed -> "analysed"
     | `Not_analysed -> "not-analysed"
     | `Interrupted -> "interrupted")

let pretty_storage fmt : storage_disposition -> unit = function
  | `None -> Format.pp_print_string fmt "none"
  | `Stored id -> Format.fprintf fmt "stored (entry %d)" id
  | `Refused reason -> Format.fprintf fmt "refused (%s)" (refusal_id reason)

(* The callstack of a call, as Eva prints it in its messages, with the number
   of each call statement after its location: two calls on one line differ. *)
let pretty_callstack fmt (cs : Callstack.t) =
  let pretty_call fmt (kf, stmt) =
    Format.fprintf fmt "%a :: %a (stmt %d) <-@ "
      Kernel_function.pretty kf
      Fileloc.pretty (Cil_datatype.Stmt.loc stmt) stmt.sid
  in
  if Self.is_message_category_enabled Log_key.callstack_hash then
    Format.fprintf fmt "<%a> " Callstack.pretty_hash cs;
  Format.fprintf fmt "@[<hv>";
  List.iter (pretty_call fmt) cs.stack;
  Format.fprintf fmt "%a@]" Kernel_function.pretty cs.entry_point

(* Ends a message with the callstack [cs] when the category [callstacks] is
   enabled, in place of the callstack of [~stacktrace:true]. [report] calls
   it only when the category [cache] is enabled too. *)
let append_callstack cs fmt =
  if Self.is_message_category_enabled Log_key.callstacks then
    Format.fprintf fmt "@\nstack: @[<hv>%a@]" pretty_callstack cs

(* Prints the dispositions of the call [call] under the message category.
   It is called while [call.callstack] is the current callstack, which the
   message ends with when the category [callstacks] is enabled. *)
let report ?collector ?produced call ~lookup ~execution ~storage =
  let with_callstack = Self.is_message_category_enabled mkey in
  let show_produced =
    Option.is_some produced && Self.is_message_category_enabled producer_mkey
  in
  let mkey = if show_produced then producer_mkey else mkey in
  if show_produced || Self.is_message_category_enabled mkey then
    let pretty_call fmt =
      let pretty_collector fmt = function
        | None -> ()
        | Some (Ok ()) -> Format.pp_print_string fmt "; collector: would-store"
        | Some (Error reason) ->
          Format.fprintf fmt "; collector: refused (%s)"
            (Body_access.Result.refusal_id reason)
      in
      let pretty_produced fmt = function
        | None -> ()
        | Some (Ok id) ->
          Format.fprintf fmt "; producer: stored (entry %d)" id
        | Some (Error reason) ->
          Format.fprintf fmt "; producer: refused (%s)"
            (Cache_producer.refusal_id reason)
      in
      Format.fprintf fmt
        "call to %a: lookup: %a; execution: %a; storage: %a%a%a"
        Kernel_function.pretty call.kf
        pretty_lookup lookup pretty_execution execution pretty_storage storage
        pretty_collector collector
        pretty_produced
        (if show_produced then produced else None)
    in
    let append =
      if with_callstack then append_callstack call.callstack else ignore
    in
    match Callstack.top_callsite call.callstack with
    | Kstmt stmt ->
      let loc = Cil_datatype.Stmt.loc stmt in
      Self.feedback ~mkey ~loc ~append "%t" pretty_call
    | Kglobal -> Self.feedback ~mkey ~append "%t" pretty_call

type delivery = {
  safety : Safety_part.t;
  categories : (string * Log.warn_status) list;
}

(* ----- Seam -------------------------------------------------------------- *)

let include_supplied stack entry ~returns =
  if Body_access.is_recording () then begin
    let module Entry = Cache_entry.Cvalue in
    let sweeps, hint_generation, functions =
      match Entry.dependencies entry with
      | None -> Base.Hptset.empty, None, []
      | Some d -> d.sweeps, d.hint_generation, d.used_functions
    in
    Body_access.include_hit stack (Entry.reference entry)
      ~footprint:(Entry.footprint entry) ~key:(Entry.key entry) ~returns
      ~sweeps ~hint_generation ~functions ~observation:(Entry.observation entry)
  end

module Make
    (Value : Datatype.S)
    (Domain : Engine_abstractions_sig.Domain)
= struct

  module Memexec = Mem_exec.Make (Value) (Domain)
  module Supplied = Supplied_entries.Lookup (Domain)
  module Producer = Cache_producer.Make (Domain)

  (* What a lookup with no candidate leaves for the storage: the cache
     consulted, with the argument values of the key of memexec, or the
     supplied entries rejected. *)
  type pending =
    | No_cache
    | Memexec of Value.t or_bottom list
    | Supplied of (int * Supplied_entries.rejection) list

  type hit_source =
    | Supplied_entry of Supplied_entries.entry * (string * Log.warn_status) list
    | Legacy_trace of Body_access.call_trace option

  type lookup =
    | No_candidate of pending
    | Hit of int * (Partition.key * Domain.t) list * hit_source

  (* Lookup in the entries supplied by a test module. *)
  let lookup_supplied call state =
    let kf = call.kf in
    let categories = Body_access.warn_categories () in
    let Supplied_entries.{ rejected; hit } =
      Supplied.find call.callstack state
    in
    let count_rejection (_, reason) =
      let id = Supplied_entries.rejection_id reason in
      Statistics.(incr (cache_rejected id) kf)
    in
    List.iter count_rejection rejected;
    match hit with
    | None -> No_candidate (Supplied rejected)
    | Some (entry, states) ->
      let id = Supplied_entries.id entry in
      Statistics.(incr cache_hits kf);
      report call ~lookup:{ rejected; hit = Some id }
        ~execution:`Not_analysed ~storage:`None;
      Hit (id, states, Supplied_entry (entry, categories))

  let lookup call state =
    let kf = call.kf in
    if not (Parameters.Memexec.get ())
    then No_candidate No_cache
    else if Supplied_entries.active ()
    then lookup_supplied call state
    else
      let args =
        List.map (fun {avalue} -> Eval.value_assigned avalue) call.arguments
      in
      match Memexec.reuse_previous_call kf state args with
      | None ->
        Statistics.(incr memexec_misses kf);
        No_candidate (Memexec args)
      | Some (states, id) ->
        Statistics.(incr memexec_hits kf);
        report call ~lookup:{ no_candidate with hit = Some id }
          ~execution:`Not_analysed ~storage:`None;
        Hit (id, states, Legacy_trace (Cache_call_trace.find id))

  (* The lookup disposition of a call that found no candidate. *)
  let lookup_disposition = function
    | No_cache | Memexec _ -> no_candidate
    | Supplied rejected -> { rejected; hit = None }

  let store ~save_results ~safety call state pending call_result footprint =
    let kf = call.kf in
    let storage =
      match pending with
      | No_cache -> `Refused `Disabled
      | Supplied _ ->
        Statistics.(incr (cache_refused (refusal_id `Supplied_only)) kf);
        `Refused `Supplied_only
      | Memexec args ->
        match Memexec.store_computed_call kf state args call_result with
        | Ok id ->
          Statistics.(incr memexec_stored kf);
          `Stored id
        | Error reason ->
          let reason = (reason :> refusal) in
          Statistics.(incr (memexec_refused (refusal_id reason)) kf);
          `Refused reason
    in
    (match storage, footprint with
     | `Stored id, Some observation -> Cache_call_trace.remember id observation
     | _ -> ());
    let collector, produced =
      match footprint with
      | None -> None, None
      | Some footprint ->
        let verdict = Body_access.verdict footprint in
        (match verdict with
         | Ok () -> Statistics.(incr collector_would_store kf)
         | Error reason ->
           let reason = Body_access.Result.refusal_id reason in
           Statistics.(incr (collector_refused reason) kf));
        let result =
          Body_access.without_recording (fun () ->
              Producer.store ~save_results ~safety call.callstack state
                call_result footprint verdict)
        in
        (match result with
         | Ok _ -> Statistics.(incr (cache_produced ()) kf)
         | Error reason ->
           let reason = Cache_producer.refusal_id reason in
           Statistics.(incr (cache_production_refused reason) kf));
        Some verdict, Some result
    in
    let entry_id = Cache_entry.Cvalue.id in
    let reported = Option.map (Result.map entry_id) produced in
    report ?collector ?produced:reported call
      ~lookup:(lookup_disposition pending) ~execution:`Analysed ~storage;
    Stdlib.Option.bind produced Result.to_option

  (* Called while an exception leaves the analysis of a body. A failure of
     the report, for instance in a listener of the log, must not replace this
     exception. *)
  let interrupted call pending =
    try
      report call ~lookup:(lookup_disposition pending)
        ~execution:`Interrupted ~storage:`None
    with _ -> ()
end
