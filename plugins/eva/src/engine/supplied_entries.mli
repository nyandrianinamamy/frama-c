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

(** The blocks a statement may read and the blocks it may write. *)
type footprint = Cache_entry.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
}

(** [supply kf ~key ~input ~footprint ~exit] supplies an entry for the body
    of [kf], built by {!Cache_entry.Make.make} from these arguments, and
    returns it. Entries are identified by 1, 2, ... in the order in which
    they are supplied, and the oldest matching entry is used at a call. Each
    exit state gets the empty partition key, and records as possible holders
    of the address of a local variable the blocks it binds to a value that
    may contain such an address.
    Raises [Invalid_argument] if [key] is not closed in [input], or if an
    exit state does not bind a written block that exists at the exit of the
    body: every written block but the locals of its inner blocks. The
    written blocks include the block of the value returned by [kf], if
    any. *)
val supply :
  kernel_function -> key:Base.Hptset.t -> input:Cvalue.Model.t ->
  footprint:footprint -> exit:Cvalue.Model.t list -> entry

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
    current project when the analysis started. *)
val active : unit -> bool

(** Why a supplied entry is not used for a call. *)
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

  (** [find kf state] applies the reuse operation ({!Cache_entry.Make.find})
      to the entries supplied for [kf], at a call whose input is [state].
      When the active domains are not the cvalue domain alone, or when a
      component listed under [`Consumer] is enabled, every entry is rejected
      for this reason. *)
  val find : kernel_function -> Domain.t -> Domain.t lookup
end
