(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

module Skipped =
  State_builder.Set_ref (Kernel_function.Set)
    (struct
      let name = "Eva.Skipped_visits.Skipped"
      let dependencies = [ Self.state ]
    end)

let skip_visits = Skipped.add

let visits_skipped kf = not (Skipped.is_empty ()) && Skipped.mem kf

let visits_skipped_at stmt =
  not (Skipped.is_empty ())
  && Skipped.mem (Kernel_function.find_englobing_kf stmt)

let complete = Skipped.is_empty

let get = Skipped.get
let set = Skipped.set
