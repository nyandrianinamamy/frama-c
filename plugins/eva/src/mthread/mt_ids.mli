(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type state = Mt_memory.Types.state
type value = Mt_memory.Types.value

(** Type associated to unique ids. *)
module type Data = sig
  type t

  (** Datatype witness. *)
  val repr : t

  (** Short name of the type, used in datatype names and log messages. *)
  val name : string

  (** Prints a value. Its id is also given, if needed. *)
  val pretty : Format.formatter -> t * int -> unit

  (** The C variable used by the Cvalue domain to propagate information
      represented by the type (threads, mutexes or message queues).*)
  val array_of_ids : unit -> Cil_types.varinfo
end

(* Identity used to group different values to the same id. *)
module type Identity = sig
  type t
  val repr : t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val hash : t -> int
end

module type S = sig
  include Datatype.S_with_collections
  val label : t -> string

  (** [id t] returns the unique id associated with [t]. *)
  val id : t -> int

  (** Returns the value associated to a given id, or None if there isn't any. *)
  val find : int -> t option

  val read_state : state -> t -> value
  val read_state_enumerate : int -> state -> t -> int list Mt_memory.conversion
  val write_state : state -> t -> int -> state
  val replace_value : state -> t -> before:int -> after:int -> state

  (** Clears all previously created ids. *)
  val clear : unit -> unit
end

(** Build a datatype of Data.t associated with unique ids. *)
module Make (Identity : Identity) (Data : Data) : sig
  include S
  val get : t -> Data.t

  (** [create identity data] associates a unique id to [data] with memoization
      over [identity]: it returns the same value as any previous call with the
      same [identity], if any. Function [clear] resets this memoization. *)
  val create : Identity.t -> Data.t -> t

  (** Associates a unique id to a global value, i.e. a value created before
      the analysis and which always remains valid (unaffected by [clear]).  *)
  val create_global : Data.t -> t

  (** Has a value already been created with this identity? *)
  val mem_identity : Identity.t -> bool

  (** Applies the given function to all values created by [create]. *)
  val fold_identity : (Identity.t -> t -> 'a -> 'a) -> 'a -> 'a
end
