(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** The paths of the body of a heap call, for the hit log (see {!Hit_log}):
    at each point of the body, the blocks that the heap effects of the call
    cover, and the blocks swept on every path from the start of the body to
    the point, or on some path only. The paths are those of the analysis of
    the body: an edge of the automaton through which the analysis propagated
    no state is on no path. *)

(** The blocks swept on every path, and those swept on some path only. The
    two sets are disjoint. A block is swept on a path when a release on this
    path turns the pointers to it into escaping addresses. A release that
    joins these pointers with escaping addresses, instead of replacing them,
    sweeps on some path only. *)
type sweeps = private { every: Base.Hptset.t; some: Base.Hptset.t }

(** No block swept. *)
val no_sweep: sweeps

(** [sweep ~exact block]: [block] swept on every path if [exact], on some
    path only otherwise. *)
val sweep: exact:bool -> Base.t -> sweeps

(** All the blocks of [sweeps], swept on some path only. *)
val weaken: sweeps -> sweeps

(** The sweeps of two alternatives, such as two paths or two evaluations of a
    call: a block swept on every path of both is swept on every path; any
    other block swept in one of them is swept on some path only. *)
val merge: sweeps -> sweeps -> sweeps

(** [sequence first next]: the sweeps of [first], then of [next]. A block
    swept on every path of one of them is swept on every path. *)
val sequence: sweeps -> sweeps -> sweeps

(** The blocks of [sweeps] that satisfy [f], with their class. *)
val filter: (Base.t -> bool) -> sweeps -> sweeps

(** What the heap effects give at a point: the blocks they cover, and the
    sweeps. *)
type t = { covered: Base.Hptset.t; sweeps: sweeps }

(** Nothing covered, no block swept. *)
val empty: t

(** The two alternatives: the blocks covered in either, and the sweeps
    merged, see {!merge}. *)
val join: t -> t -> t

(** [after value next]: the blocks covered in either, and the sweeps of
    [value] followed by those of [next], see {!sequence}. *)
val after: t -> t -> t

(** [compute automaton ~fired ~edge ~vertex] is the value at each vertex of
    [automaton] that the edges of [fired] reach from the entry point, on the
    paths made of these edges. Each edge [e] adds [edge e] after the value
    at its origin, and each vertex [v] adds [vertex v] on entry, the entry
    point included: their blocks are covered from there on, and their sweeps
    follow those of the path, see {!sequence}. The values of the paths that
    reach a vertex are joined, see {!join}. *)
val compute:
  Eva_automata.automaton ->
  fired:(Eva_automata.edge -> bool) ->
  edge:(Eva_automata.edge -> t) ->
  vertex:(Eva_automata.vertex -> t) ->
  t Eva_automata.Vertex.Hashtbl.t
