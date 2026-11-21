(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

let observe _callstack kf pre = function
  | `Spec _ when Kernel_function.get_name kf = "choose" ->
    let deps = Eva.Logic_inout.specification_deps kf ~pre in
    Kernel.result "Specification logic inputs for %a: @[<hov>%a@]"
      Kernel_function.pretty kf Memory_zone.pretty deps
  | _ -> ()

let () = Eva.Cvalue_callbacks.register_call_results_hook observe
