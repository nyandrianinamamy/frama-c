(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** The unit domain infers no property on the program.
    It is used when no other domain is enabled. *)

(** Value and location abstractions to be used with the unit domain. *)
module type Dependencies = sig
  type value
  type location
  val value: value Abstract_value.dependencies
  val location: location Abstract_location.dependencies
end

(** Build the unit domain over any value and location abstractions. *)
module Make (Deps: Dependencies) :
  Abstract_domain.Leaf with type context = unit
                        and type value = Deps.value
                        and type location = Deps.location
