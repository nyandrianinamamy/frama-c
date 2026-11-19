(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

(** This modules stores the alarms and properties for which a red status has
    been emitted. *)

(* Remembers that a red status has been emitted for an alarm or a property at
   the given kinstr. *)
val add_red_alarm:    kinstr -> Alarms.t -> unit
val add_red_property: kinstr -> Property.t -> unit

type alarm_or_property = Safety_part.red_target =
  | Alarm of Alarms.t | Prop of Property.t

(** [add_red_context kinstr target] records that [target] got a red status
    at [kinstr] in the current callstack: the table keeps the callstack
    once, and the hooks registered by {!register_hook} run. The two
    functions above call it, [add_red_property] twice for an instance of a
    precondition. A hit delivers the red contexts of its entry through it,
    each time the body set one, in the order of the analysis of the body
    (see {!Safety_part}). *)
val add_red_context: kinstr -> alarm_or_property -> unit

(** Folds over the alarms and properties that got a red status, with the
    callstacks in which they got it, [None] standing for no callstack. *)
val fold_contexts:
  (kinstr -> alarm_or_property -> Callstack.t option list -> 'a -> 'a) ->
  'a -> 'a

(* Whether a red status has been emitted for a property in any callstack. *)
val is_red: Property.t -> bool

(* If option -eva-report-red-statuses has been set, reports red statuses in
   a csv file. *)
val report: unit -> unit

(* Register a hook that is called each time a red status is set. The
   collector of block accesses refuses a body during which the hook is
   called ([Hook.Opaque]): the client is not audited. *)
val register_hook: (alarm_or_property -> unit) -> unit
