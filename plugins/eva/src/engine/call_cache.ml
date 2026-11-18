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
]

let refusals : refusal list =
  [ `Disabled; `Not_cacheable; `No_inout; `Footprint_top; `Relate_top;
    `Relate_unclosed; `Exception ]

let refusal_id : refusal -> string = function
  | `Disabled -> "disabled"
  | `Not_cacheable -> "not-cacheable"
  | `No_inout -> "no-inout"
  | `Footprint_top -> "footprint-top"
  | `Relate_top -> "relate-top"
  | `Relate_unclosed -> "relate-unclosed"
  | `Exception -> "exception"

(* No verbosity level: the category is enabled only by -eva-msg-key. *)
let mkey =
  let reasons = String.concat ", " (List.map refusal_id refusals) in
  Self.register_message_category "cache"
    ~help:("print the dispositions of each call analysed through the body \
            of the called function or answered by the cache of calls: \
            lookup in the cache (no-candidate or hit), execution of the body \
            (analysed, not-analysed or interrupted) and storage of the \
            result (stored, none, or refused with one of the reasons: "
           ^ reasons ^ ")")

let new_counter = Mem_exec.new_counter

let cleanup_results = Mem_exec.cleanup_results

(* ----- Report of the dispositions of a call ------------------------------ *)

type lookup_disposition = [ `No_candidate | `Hit of int ]
type execution_disposition = [ `Analysed | `Not_analysed | `Interrupted ]
type storage_disposition = [ `None | `Stored of int | `Refused of refusal ]

let pretty_lookup fmt : lookup_disposition -> unit = function
  | `No_candidate -> Format.pp_print_string fmt "no-candidate"
  | `Hit id -> Format.fprintf fmt "hit (entry %d)" id

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

(* Prints the dispositions of the call [call] under the message category. *)
let report call ~lookup ~execution ~storage =
  if Self.is_message_category_enabled mkey then
    let pretty_call fmt =
      Format.fprintf fmt "call to %a: lookup: %a; execution: %a; storage: %a"
        Kernel_function.pretty call.kf
        pretty_lookup lookup pretty_execution execution pretty_storage storage
    in
    match Callstack.top_callsite call.callstack with
    | Kstmt stmt ->
      let loc = Cil_datatype.Stmt.loc stmt in
      Self.feedback ~mkey ~loc "%t" pretty_call
    | Kglobal -> Self.feedback ~mkey "%t" pretty_call

(* ----- Seam -------------------------------------------------------------- *)

module Make
    (Value : Datatype.S)
    (Domain : Engine_abstractions_sig.Domain)
= struct

  module Memexec = Mem_exec.Make (Value) (Domain)

  (* What a lookup with no candidate leaves for the storage: whether a cache
     was consulted, and the argument values of its key. *)
  type pending =
    | No_cache
    | Memexec of Value.t or_bottom list

  type lookup =
    | No_candidate of pending
    | Hit of int * (Partition.key * Domain.t) list

  let lookup call state =
    let kf = call.kf in
    if not (Parameters.Memexec.get ())
    then No_candidate No_cache
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
        report call
          ~lookup:(`Hit id) ~execution:`Not_analysed ~storage:`None;
        Hit (id, states)

  let store call state pending call_result =
    let kf = call.kf in
    let storage =
      match pending with
      | No_cache -> `Refused `Disabled
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
    report call ~lookup:`No_candidate ~execution:`Analysed ~storage

  (* Called while an exception leaves the analysis of a body. A failure of
     the report, for instance in a listener of the log, must not replace this
     exception. *)
  let interrupted call =
    try
      report call ~lookup:`No_candidate ~execution:`Interrupted ~storage:`None
    with _ -> ()
end
