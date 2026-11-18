(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Cache entries and the reuse operation.

    A cache entry is the stored result of analysing one statement from one
    abstract input. An entry holds:
    - its statement, the body of a function;
    - its matching key: a set of blocks, closed under [relate] in the stored
      input, and the stored input filtered to these blocks;
    - its footprint: the blocks the statement may read, and three sets of
      blocks it may write (see {!footprint});
    - its Exit part: the abstract states at the exits of the statement, each
      with its partition key.

    The reuse operation ({!Make.find}) takes the candidate entries of a call,
    oldest first, and the input of the call. A candidate matches when the
    input filtered to its key is equal to its stored input and when its key is
    closed under [relate] in the input. The oldest matching candidate is used:
    each state at the end of the call is the input of the call in which the
    blocks written on a path that reaches an exit are taken from an exit
    state, through [reuse]. The key has no argument, call-site or callstack
    component. *)

open Cil_types

(** The statement of an entry. The only unit is the body of a function. *)
type statement = Body of kernel_function

(** The blocks that a statement analysed from one input may access. The
    footprint is R ∪ W, and W_sure ⊆ W_exit ⊆ W. A block written only on
    paths that reach no exit is in W and not in W_exit: at an exit it holds
    the value it had in the input.
    - [read], R: the blocks it may read;
    - [written], W: the blocks it may write;
    - [written_exit], W_exit: the blocks it may write on a path that reaches
      an exit of the statement;
    - [written_sure], W_sure: the blocks it certainly and fully overwrites on
      every path that reaches an exit. *)
type footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

(** Why a candidate entry is not used for a call. *)
type rejection = [
  | `Key_differs
  (** The input of the call filtered to the key of the entry differs from the
      stored input. *)
  | `Key_unclosed
  (** [relate] relates the key of the entry to blocks outside the key in the
      input of the call. *)
]

(** Stable identifier of a reason: [key-differs] for [`Key_differs] and
    [key-unclosed] for [`Key_unclosed]. *)
val rejection_id : rejection -> string

(** The operations of an abstract domain used by the reuse operation. *)
module type Domain = sig
  type t
  val equal : t -> t -> bool
  val pretty : Format.formatter -> t -> unit
  val relate : Base.Hptset.t -> t -> Base.SetLattice.t
  val filter : Base.Hptset.t -> t -> t

  (** [reuse w ~current_input ~previous_output] is [current_input] in which
      the blocks of [w] are taken from [previous_output]: it takes nothing
      else from [previous_output]. *)
  val reuse : Base.Hptset.t -> current_input:t -> previous_output:t -> t
end

module Make (Domain : Domain) : sig

  (** A cache entry whose states belong to [Domain]. *)
  type t

  (** [make ~id statement ~key ~input ~footprint ~exit] builds an entry
      identified by [id]. The stored input is [input] filtered to [key]. The
      block that holds the value returned by the function, if any, is added
      to the three written sets of [footprint]: it is fully overwritten on
      every path that reaches an exit. Each exit state is filtered to [key]
      and to the written blocks.
      Raises [Invalid_argument] if W_sure ⊆ W_exit ⊆ W does not hold, if
      [key] does not contain R ∪ (W_exit \ W_sure), or if [key] is not closed
      under [Domain.relate] in [input]. *)
  val make :
    id:int -> statement -> key:Base.Hptset.t -> input:Domain.t ->
    footprint:footprint -> exit:(Partition.key * Domain.t) list -> t

  (** The identifier given to {!make}. *)
  val id : t -> int

  val statement : t -> statement

  (** The blocks of the matching key. *)
  val key : t -> Base.Hptset.t

  (** The stored input, filtered to the key. *)
  val input : t -> Domain.t

  (** The footprint, with the return block among the three written sets. *)
  val footprint : t -> footprint

  (** The Exit part: the exit states, filtered to the key and to the written
      blocks, with their partition keys. *)
  val exit : t -> (Partition.key * Domain.t) list

  val pretty : Format.formatter -> t -> unit

  (** Result of the reuse operation for one call. *)
  type result = {
    rejected : (t * rejection) list;
    (** The candidates examined and rejected, oldest first. *)
    hit : (t * (Partition.key * Domain.t) list) option;
    (** The candidate used, if any, and the states at the end of the call. *)
  }

  (** [find candidates state] applies the reuse operation to a call whose
      input is [state]. The [candidates] are given oldest first. They are
      examined in this order until one matches, and that one is used: the
      states at the end of the call are
      [reuse written_exit ~current_input:state ~previous_output:s] for each
      exit state [s] of the entry, with its partition key, where
      [written_exit] is W_exit of its footprint. Every other block, those of
      the key and those of W \ W_exit included, keeps its value in [state]. *)
  val find : t list -> Domain.t -> result
end
