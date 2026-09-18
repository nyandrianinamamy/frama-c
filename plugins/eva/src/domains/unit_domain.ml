(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Static = struct
  module D = struct
    include Datatype.Unit
    type state = t
    let name = "unit"

    let top = ()
    let is_included _ _ = true
    let join _ _ = ()
    let widen _ _ _ _ = ()
    let narrow _ _ = `Value ()
  end

  include D
  include Domain_builder.Complete (D)
end

module type Dependencies = sig
  type value
  type location
  val value: value Abstract_value.dependencies
  val location: location Abstract_location.dependencies
end

module Make (Deps : Dependencies) = struct

  include Static
  type value = Deps.value
  type location = Deps.location
  type origin

  let value_dependencies = Deps.value
  let location_dependencies = Deps.location

  let rec get_top: type v. v Abstract_value.dependencies -> v = function
    | Leaf (module Value) -> Value.top
    | Node (d1, d2) -> (get_top d1, get_top d2)

  let top_value = get_top Deps.value
  let eval_top = `Value (top_value, None), Alarmset.all
  let extract_expr ~oracle:_ _ _ _ = eval_top
  let extract_lval ~oracle:_ _ _ _ _ = eval_top

  let update _ _ = `Value ()
  let assign ~pos:_ _ _ _ _ _ = `Value ()
  let assume ~pos:_ _ _ _ _ = `Value ()
  let start_call ~pos:_ _ _ _ _ = `Value ()
  let finalize_call ~pos:_ _ _ ~pre:_ ~post:_ = `Value ()
  let show_expr _ _ _ _ = ()

  let logic_assign _ _ _ = ()

  let enter_scope _ _ _ = ()
  let leave_scope _ _ _ = ()

  let empty () = ()
  let initialize_variable _ _ ~initialized:_ _ _ = ()
  let initialize_variable_using_type _ _ _  = ()

  let relate _ () = Base.SetLattice.empty
  let overwrite _ ~on:_ ~by:_ = ()
end
