(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Cache entries supplied by a test module to the reuse operation.

    This module is for tests only: entries are supplied by test modules, and
    no part of the analyzer supplies any. The entries hold states of the
    cvalue domain (see {!Cache_entry}).

    The cache of calls of an analysis is chosen when the analysis starts.
    When entries were supplied in the current project, it is the reuse
    operation on the supplied entries, and memexec is not consulted: no call
    of this analysis is answered by memexec, and no result is stored.
    Otherwise memexec is the cache of calls, as before, and entries supplied
    during the analysis are not used by it. Option [-eva-no-memexec]
    disables both. See {!Call_cache} for the dispositions printed at each
    call. *)

open Cil_types

(** A cache entry with states of the cvalue domain. *)
type entry

(** The footprint of an entry: R, W, W_exit and W_sure (see
    {!Cache_entry.footprint}). *)
type footprint = Cache_entry.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

(** [supply kf ~key ~input ~footprint ~exit] supplies an entry for the body
    of [kf], built by {!Cache_entry.Make.make} from these arguments, and
    returns it. [exit] lists the exit states of the body with their
    partition keys: a body that never returns has no exit state, and its
    entry has the empty list. Entries are identified by 1, 2, ... in the
    order in which they are supplied, and the oldest matching entry is used
    at a call. Each exit state records as possible holders of the address of
    a local variable the blocks it binds to a value that may contain such an
    address.

    The entry is used as given: nothing checks that it describes the body of
    [kf], and a false entry gives a false result at a hit. The caller of
    [supply] owes, for every concrete execution of the body that starts in a
    state covered by [input]:
    - R covers every block that the body may read, through a pointer
      included; a block designated by a pointer of the key is not in the key
      unless it is listed in it;
    - W covers every block that the body may write; W_exit covers every
      block that the body may write on a path that reaches an exit, even
      when the write leaves the value of the input;
      W_sure holds only blocks certainly and fully overwritten on every path
      that reaches an exit;
    - the key contains R ∪ (W_exit \ W_sure), and the body neither frees nor
      allocates a block, nor ends the lifetime of a block other than its own
      locals;
    - each execution that returns ends in a memory covered by one of the
      exit states; this includes the effect of leaving the scope of the
      locals of the body on the blocks that may hold their addresses, which
      the end of the call does not sweep again for the locals of inner
      blocks.

    Raises [Invalid_argument] if [input] or an exit state is [Top] or
    [Bottom]; if the written sets are not nested (W_sure ⊆ W_exit ⊆ W); if
    [key] does not contain R ∪ (W_exit \ W_sure); if [key] is not closed in
    [input]; or if an exit state does not bind a block of W_exit that exists
    at the exit of the body: every block of W_exit but the locals of its
    inner blocks. The three written sets include the block of the value
    returned by [kf], if any (see {!return_variable}). *)
val supply :
  kernel_function -> key:Base.Hptset.t -> input:Cvalue.Model.t ->
  footprint:footprint -> exit:(Partition.key * Cvalue.Model.t) list -> entry

(** Supply the key and states of an entry captured by the producer, with
    the next supplied entry identifier. The lookup checks the recorded
    sweep targets, used functions and widening generation. The fixture
    must use the same AST
    and ensure the calls meet the replay premises described on [supply].
    Supplying entries remains a test-only operation. *)
val supply_produced : Cache_producer.entry -> entry

(** The partition key of a state that no partitioning distinguishes. *)
val empty_key : Partition.key

(** [case_key kf n] is the partition key that the analysis gives to the
    [n]-th state of a disjunction at the return statement of [kf]. Two
    different [n] give two different keys. *)
val case_key : kernel_function -> int -> Partition.key

(** The variable that holds the value returned by [kf] in the exit states,
    if [kf] returns a value. *)
val return_variable : kernel_function -> varinfo option

(** The entries supplied for the body of a function, oldest first. *)
val entries : kernel_function -> entry list

(** Removes all supplied entries of the current project. *)
val clear : unit -> unit

(** {2 Content of an entry} *)

val id : entry -> int
val statement : entry -> Cache_entry.statement
val key : entry -> Base.Hptset.t
val input : entry -> Cvalue.Model.t
val footprint : entry -> footprint
val exit : entry -> (Partition.key * Cvalue.Model.t) list
val pretty : Format.formatter -> entry -> unit

(** {2 Lookup} *)

(** Whether the cache of calls of the current analysis is the reuse
    operation on the supplied entries: whether entries were supplied in the
    current project when the analysis started. The choice holds for the
    whole analysis. Within an analysis that uses the supplied entries, each
    lookup reads the entries supplied at that time, so an entry supplied
    during the analysis, by a callback for instance, is a candidate for the
    later calls of that analysis. *)
val active : unit -> bool

(** Why a supplied entry is not used for a call. When the active domains
    are not the cvalue domain alone, every candidate is rejected with
    [`Product], whatever the other reasons; otherwise, when a consumer is
    enabled, with [`Consumer]; otherwise each candidate is examined by
    {!Cache_entry.Make.find}. *)
type rejection = [
  | Cache_entry.rejection
  | `Product
  (** The active domains are not the cvalue domain alone. *)
  | `Consumer
  (** A component that resolves the identifier of a hit against the entries
      of memexec is enabled: the Inout or From plug-in, or the analysis of
      threads. *)
]

(** All reasons, in the order of their documentation. *)
val rejections : rejection list

(** Stable identifier of a reason: those of {!Cache_entry.rejection_id},
    [product] for [`Product] and [consumer] for [`Consumer]. *)
val rejection_id : rejection -> string

(** Result of a lookup. *)
type 'state lookup = {
  rejected : (int * rejection) list;
  (** The identifiers of the candidates rejected, oldest first, with their
      reasons. *)
  hit : (int * (Partition.key * 'state) list) option;
  (** The identifier of the entry used, if any, and the states at the end of
      the call. *)
}

module Lookup (Domain : sig
    type t
    val structure : t Abstract.Domain.structure
  end) : sig

  (** [find stack state] applies the reuse operation ({!Cache_entry.Make.find})
      to the entries supplied for [kf], at a call whose input is [state].
      When the active domains are not the cvalue domain alone, or when a
      component listed under [`Consumer] is enabled, every entry is rejected
      for this reason. *)
  val find : Callstack.t -> Domain.t -> Domain.t lookup
end
