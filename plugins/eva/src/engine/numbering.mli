(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** The numbered form of a cache entry (#120, section "Lookup"): its
    allocated blocks are numbered in a deterministic order, and each number
    stands for a placeholder block, so that two entries that differ only by
    the allocated blocks they use have the same numbered form.

    A placeholder is an allocated base of one of two pools, strong and weak.
    It has the strength of the block it stands for, because the rewriting of
    a memory map merges adjacent pointer fragments to a strong block and
    keeps them apart for a weak one. The strength is read from its validity
    record; the rest of the record, its type and its kind mean nothing, and
    no operation that reads them is applied to a numbered state.
    A placeholder never appears in a state of the analysis.

    Only the cvalue domain is numbered: the arguments are their cvalue
    component, and a state is a cvalue state with its clobbered set. *)

(** {2 Placeholders} *)

(** [placeholder ~weak n] is the placeholder of number [n] of the pool of
    the given strength. It is created at its first use, once per analysis,
    and shared by all entries. *)
val placeholder: weak:bool -> int -> Base.t

(** The number of a placeholder, or [None] for any other base. *)
val placeholder_number: Base.t -> int option

(** {2 Numbering} *)

(** How the numbering discovered a block. *)
type discovery =
  | Argument of int
  (** A target of the argument of this rank, from 0. *)
  | Content of Base.t
  (** A target of a value of the content of this block. *)
  | Candidate
  (** A candidate of an allocation. *)
  | No_root
  (** An allocated key block reached from no root. *)

(** A numbering in progress: the numbered blocks, and those of them already
    examined. It is persistent, so that a lookup can number the arguments
    once and continue for each stored key. *)
type t

(** Raised when a value read by the numbering may point to an unknown set of
    blocks, or when the state is top. A call whose arguments or key hold
    such a value gets no cache entry. *)
exception Unknown_targets

(** The numbering with no block. *)
val empty: t

(** [arguments args t] numbers the allocated targets of the arguments, in
    their order; within a value, by increasing identifier. It does not read
    the key. *)
val arguments: Cvalue.V.t Lattice_bounds.or_bottom list -> t -> t

(** [roots bases state t] walks the content in [state] of each block of
    [bases], in the order of their identifiers: within a block, its values by
    increasing offset, and within a value, its allocated targets by
    increasing identifier. Each target gets the next number at its first
    discovery. The blocks of [bases] are not numbered. *)
val roots: Base.Hptset.t -> Cvalue.Model.t -> t -> t

(** [drain ~is_key state t] examines each numbered block not examined yet,
    in the order of the numbers, until none is left: a block for which
    [is_key number base] holds is entered, that is, its content in [state] is
    walked as by [roots]; any other block is only mentioned. *)
val drain: is_key:(int -> Base.t -> bool) -> Cvalue.Model.t -> t -> t

(** [add discovery bases t] numbers the allocated blocks of [bases] not
    numbered yet, in the order of the list. *)
val add: discovery -> Base.t list -> t -> t

(** [of_entry ~candidates ~args ~key state] numbers the allocated blocks
    of an entry whose start state on its key [key] is [state], in the order of
    #120: the arguments; then the content of the blocks of the key that are
    not allocated, in the order of their identifiers; then each numbered
    block of the key, entered in the order of the numbers; then the
    [candidates], in the order of the list; then the allocated blocks of the
    key reached from no root, in the order of their identifiers. A numbered
    block of the key is entered whatever its discovery, so that the
    numbering ends with every block that a value of the key may point to.
    Raises [Unknown_targets]. *)
val of_entry:
  candidates:Base.t list ->
  args:Cvalue.V.t Lattice_bounds.or_bottom list ->
  key:Base.Hptset.t -> Cvalue.Model.t -> t

(** The numbered blocks, in the order of their numbers, each with its
    strength when it was numbered and its discovery. *)
val blocks: t -> (Base.t * bool * discovery) list

(** The number of a block, if numbered. *)
val number: t -> Base.t -> int option

(** {2 Rewriting} *)

(** The substitution from each numbered block to the placeholder of its
    number, of the pool of its strength when it was numbered. *)
val to_numbers: t -> Base.substitution

(** The substitution from the placeholders of [to_numbers] back to the
    numbered blocks. *)
val of_numbers: t -> Base.substitution

(** What the numbered form rewrites of a cache entry: the arguments, the
    key, the start state on the key, and the states at the exits, each a
    cvalue state with its clobbered set. *)
type entry = {
  args: Cvalue.V.t Lattice_bounds.or_bottom list;
  key: Base.Hptset.t;
  start: Cvalue.Model.t * Locals_scoping.clobbered_set;
  exits: (Cvalue.Model.t * Locals_scoping.clobbered_set) list;
}

(** [rewrite substitution entry] replaces the bases of [entry] by
    [substitution]: the targets of each value, the blocks of the key and of
    the clobbered sets, and the blocks bound in each state. It reads no
    validity and no type, except the strength of the targets of the
    rewritten values, by which the memory maps merge pointer fragments. The
    clobbered sets are copied: the record of the state is not changed. *)
val rewrite: Base.substitution -> entry -> entry

(** The allocated blocks of [entry] that are not placeholders: none in the
    numbered form of an entry, unless a block of an exit or of a clobbered
    set is not numbered. A value that may point to an unknown set of blocks
    names no block. *)
val unnumbered: entry -> Base.Hptset.t

type error =
  | Unknown (** A value of the arguments or of the key has unknown targets. *)
  | Unnumbered of Base.Hptset.t
  (** Allocated blocks left in the rewritten entry: an exit or a clobbered
      set holds a block that the numbering of the key did not reach. *)

(** [number_entry ~candidates entry] numbers the blocks of [entry] and
    rewrites it with numbers in place of its allocated blocks. *)
val number_entry:
  candidates:Base.t list -> entry -> (t * entry, error) result

(** Whether two entries are equal: their arguments, keys, states and
    clobbered sets. *)
val equal_entry: entry -> entry -> bool
