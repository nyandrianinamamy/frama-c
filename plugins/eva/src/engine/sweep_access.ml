(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

let clear_input targets model =
  if Base.Hptset.is_empty targets then true
  else
    match model with
    | Cvalue.Model.Bottom | Cvalue.Model.Top -> false
    | Cvalue.Model.Map map ->
      let check_cell value =
        let value = Cvalue.V_Or_Uninitialized.get_v value in
        match Cvalue.V.get_bases value with
        | Base.SetLattice.Top -> raise Exit
        | Base.SetLattice.Set bases ->
          if Base.Hptset.intersects bases targets then raise Exit
      in
      let check_block base offsetmap () =
        if Base.Hptset.mem base targets then raise Exit;
        Cvalue.V_Offsetmap.iter_on_values check_cell offsetmap
      in
      try Cvalue.Model.fold check_block map (); true with Exit -> false
