(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type t

type state = Mt_memory.Types.state
type value = Mt_memory.Types.value

val pretty : Format.formatter -> t -> unit

val read_id_state : state -> t -> value
val read_id_state_enumerate : int -> state -> t -> int list Mt_memory.conversion
val write_id_state : state -> t -> int -> state
val replace_id_value : state -> t -> before:int -> after:int -> state

val of_thread : Thread.t -> t
val of_mutex : Mutex.t -> t
val of_queue : Mqueue.t -> t
