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
  | Mem_exec.refusal
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
            (analysed or not-analysed) and storage of the result (stored, \
            none, or refused with one of the reasons: " ^ reasons ^ ")")

let new_counter = Mem_exec.new_counter

let cleanup_results = Mem_exec.cleanup_results

(* ----- Report of the dispositions of a call ------------------------------ *)

type lookup_disposition = [ `No_candidate | `Hit of int ]
type storage_disposition = [ `None | `Stored of int | `Refused of refusal ]

let pretty_lookup fmt : lookup_disposition -> unit = function
  | `No_candidate -> Format.pp_print_string fmt "no-candidate"
  | `Hit id -> Format.fprintf fmt "hit (entry %d)" id

let pretty_execution fmt analysed =
  Format.pp_print_string fmt (if analysed then "analysed" else "not-analysed")

let pretty_storage fmt : storage_disposition -> unit = function
  | `None -> Format.pp_print_string fmt "none"
  | `Stored id -> Format.fprintf fmt "stored (entry %d)" id
  | `Refused reason -> Format.fprintf fmt "refused (%s)" (refusal_id reason)

(* Prints the dispositions of the call [call] under the message category. *)
let report call ~lookup ~analysed ~storage =
  if Self.is_message_category_enabled mkey then
    let pretty_call fmt =
      Format.fprintf fmt "call to %a: lookup: %a; execution: %a; storage: %a"
        Kernel_function.pretty call.kf
        pretty_lookup lookup pretty_execution analysed pretty_storage storage
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

  type lookup =
    | No_candidate
    | Hit of int * (Partition.key * Domain.t) list

  let arguments call =
    List.map (fun {avalue} -> Eval.value_assigned avalue) call.arguments

  let lookup call state =
    let kf = call.kf in
    let previous_call =
      if Parameters.Memexec.get ()
      then Memexec.reuse_previous_call kf state (arguments call)
      else None
    in
    match previous_call with
    | None ->
      Statistics.(incr memexec_misses kf);
      No_candidate
    | Some (states, id) ->
      Statistics.(incr memexec_hits kf);
      report call ~lookup:(`Hit id) ~analysed:false ~storage:`None;
      Hit (id, states)

  let store call state call_result =
    let kf = call.kf in
    let storage =
      if Parameters.Memexec.get ()
      then
        let args = arguments call in
        (Memexec.store_computed_call kf state args call_result
         :> (int, refusal) result)
      else Error `Disabled
    in
    let storage =
      match storage with
      | Ok id ->
        Statistics.(incr memexec_stored kf);
        `Stored id
      | Error reason ->
        Statistics.(incr (memexec_refused (refusal_id reason)) kf);
        `Refused reason
    in
    report call ~lookup:`No_candidate ~analysed:true ~storage
end
