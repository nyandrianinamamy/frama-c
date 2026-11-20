(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

let initial_state_read =
  ref (fun () -> Cvalue_results.get_state Domain_store.Initial)

let before_read = ref (fun stmt -> Cvalue_results.get_state (Before stmt))

let initial_state () = !initial_state_read ()
let before stmt = !before_read stmt

let install ~initial_state ~before =
  initial_state_read := initial_state;
  before_read := before
