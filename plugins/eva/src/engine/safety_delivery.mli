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
    - the message of a status through {!Safety_part.status_message}, so
      that the action of its message category applies, and a text printed
      before at the same position is not printed again;
    - a red context through {!Red_statuses.add_red_context}, which adds the
      callstack of the write to the contexts of its alarm or property, and
      runs the hooks of red statuses as many times as the body set it in a
      row. The writes are delivered in the order of the Safety part, so the
      hooks of red statuses and the messages run in the order of the
      analysis of the body. *)
val deliver : Callstack.t -> Safety_part.t -> unit

(** {2 Functions with skipped visits}

    A hit delivers the Safety part of its entry, but saves no state for the
    statements of the called function: the visits of these statements by
    the call are skipped. Until a hit delivers the statements it reaches
    (issue #48), the passes run at the end of the analysis must not
    conclude from the absence of a state at a statement of such a function:
    it is not dead, and the states saved there are those of the analysed
    calls only. The functions called by the body of an entry are skipped as
    well; there are none, since an entry is refused for a body that may
    call a function that has a body (see {!Supplied_entries.supply}). *)

(** [skip_visits kf] records that a hit has answered a call of [kf] in the
    current analysis. The record is a state of the analysis, and is reset
    with it. *)
val skip_visits : Cil_types.kernel_function -> unit

(** Whether a hit has answered a call of the function in the current
    analysis. *)
val visits_skipped : Cil_types.kernel_function -> bool

(** Whether a hit has answered a call of the function that contains the
    statement, in the current analysis. *)
val visits_skipped_at : Cil_types.stmt -> bool
