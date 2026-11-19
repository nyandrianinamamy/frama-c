(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

let deliver_write (write : Safety_part.write) () =
  match write with
  | Emitted_alarm { kinstr; alarm; status; emitter } ->
    let pos = Position.of_kinstr kinstr (Current_callstack.get_exn ()) in
    Alarmset.deliver ~pos ~emitter alarm status
  | Emitted_status { property; status; emitter } ->
    Body_access.record Statuses;
    Safety_part.emit_status emitter property status
  | Status_message { status; loc; stacktrace; text } ->
    Safety_part.status_message status ~loc ~stacktrace text
  | Red_context { kinstr; target; count } ->
    Red_statuses.add_red_context ~count kinstr target

let deliver callstack part =
  let deliver write =
    let callstack = Safety_part.reroot callstack (Safety_part.frames write) in
    Current_callstack.with_callstack callstack (deliver_write write) ()
  in
  List.iter deliver part

