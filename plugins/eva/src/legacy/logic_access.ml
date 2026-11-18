(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

type kind = Annotation | Contract

let current = ref None

let with_clause kind f =
  if not (Body_access.is_recording ()) then f ()
  else
    let previous = !current in
    current := Some kind;
    Fun.protect f ~finally:(fun () -> current := previous)

let is_recording () =
  Option.is_some !current && Body_access.is_recording ()

let unknown_read () =
  match !current with
  | Some Annotation -> Body_access.unknown_read Annotation
  | Some Contract -> Body_access.unknown_read Contract
  | None -> ()

let refuse_side_table () =
  if is_recording () then Body_access.refuse Side_table

let read loc =
  if is_recording () then
    match Addresses.Bits.get_bases loc.Locations.addr with
    | Base.SetLattice.Top -> unknown_read ()
    | Base.SetLattice.Set _ -> Body_access.read loc

let check_bound = function
  | Base.SetLattice.Top -> unknown_read ()
  | Base.SetLattice.Set _ -> ()

let designate value =
  if is_recording () then begin
    Body_access.designate value;
    check_bound (Cvalue.V.get_bases value)
  end

let designate_bits addr =
  if is_recording () then begin
    Body_access.designate_bits addr;
    check_bound (Addresses.Bits.get_bases addr)
  end

let designate_raw value =
  if is_recording () then
    designate (Cvalue.V_Or_Uninitialized.get_v value)

module Shape = Hptmap.Shape (Base.Base)

let record_reduction ~before ~after =
  let open Cvalue.Model in
  if is_recording () && not (equal before after) then
    match before, after with
    | _, Bottom -> ()
    | Map before, Map after ->
      let only_one map =
        Shape.iter (fun base _ -> Body_access.may_write_base base) map
      in
      let both base before after =
        if not (Cvalue.V_Offsetmap.equal before after) then
          Body_access.may_write_base base
      in
      Shape.fold2_join_heterogeneous
        ~cache:Hptmap_sig.NoCache ~empty_left:only_one ~empty_right:only_one
        ~both ~join:(fun () () -> ()) ~empty:()
        (shape before) (shape after)
    | _ ->
      Body_access.unknown_write ();
      Body_access.refuse Footprint_top
