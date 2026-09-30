(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

val fresh: Obfuscator_kind.t -> string -> string
(** Generate a fresh name of the given kind *)

val fresh_acsl_string_literal: Cil_types.logic_constant -> string
(** Generate a macro name for an ACSL string literal. *)

val pp_acsl_string_literal_dict: Format.formatter -> unit
(** prints #define directives for all registered ACSL string literals. *)

val has_acsl_string_literals: unit -> bool
(** true if there are ACSL string literals. *)

val pretty_kind: Format.formatter -> Obfuscator_kind.t -> unit
val pretty: Format.formatter -> unit

val mark_as_computed: unit -> unit
val is_computed: unit -> bool
