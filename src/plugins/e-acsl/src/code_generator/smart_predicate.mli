(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

open Cil_types

val prel :
  ?smart:bool ->
  ?loc:Fileloc.t ->
  ?names:string list ->
  relation ->
  term ->
  term ->
  predicate
(** create a relation predicate. Optimisation depends on the [-e-acsl-O]
    option and [?smart]. *)

val pand :
  ?smart:bool ->
  ?loc:Fileloc.t ->
  ?names:string list ->
  predicate ->
  predicate ->
  predicate
(** create a conjunction. Optimisation depends on the [-e-acsl-O] option and
    [?smart]. *)
