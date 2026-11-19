(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Delivery of the Safety part of a cache entry at a hit. *)

(** [deliver callstack part] performs again, in their order, the writes of
    [part] for a call with [callstack]. Each write is made while the current
    callstack is the one obtained by putting its frames on top of
    [callstack]. It is also recorded in the Safety part of the body being
    analysed, if any. Each write goes through the function that the body
    uses to emit it:
    - an alarm through {!Alarmset.deliver}, so that the kernel combines its
      status with the existing one;
    - a status through {!Safety_part.emit_status}, so that the kernel
      combines it with the statuses that the same emitter emitted before on
      the same property;
    - a red context through {!Red_statuses.add_red_context}, which adds the
      callstack of the write to the contexts of its alarm or property. *)
val deliver : Callstack.t -> Safety_part.t -> unit
