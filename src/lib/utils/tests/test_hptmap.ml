(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* Test of [fold2_join_homogeneous] of {!Hptmap.Shape}, on pairs of random
   maps, most of them sharing subtrees:
   - its result is that of [fold2_join_heterogeneous], and that of a direct
     computation, without cache and with a cache, both when [both] and [same]
     give nothing for the keys bound to the same value in the two maps and
     when they give these bindings;
   - it never calls [both] on a key bound to the same value in the two maps,
     and it calls [same] on shared subtrees of several keys. *)

let%test "fold2_join_homogeneous" =
  let module Key = struct include Datatype.Int let id = Fun.id end in
  let module Info = struct
    let initial_values = []
    let dependencies = []
  end in
  let module M = Hptmap.Make (Key) (Datatype.Int) (Info) in
  let random = Random.State.make [| 20261122 |] in
  let random_key () =
    if Random.State.int random 8 = 0 then Random.State.bits random
    else Random.State.int random 1024
  in
  let random_value () = Random.State.int random 4 in
  let rec random_map m n =
    if n = 0 then m
    else random_map (M.add (random_key ()) (random_value ()) m) (n - 1)
  in
  let random_map n = random_map M.empty n in
  (* [m] after [n] random additions, removals and rebindings of keys. *)
  let rec change m n =
    if n = 0 then m
    else
      let keys = M.fold (fun k _ acc -> k :: acc) m [] in
      let some_key () =
        List.nth keys (Random.State.int random (List.length keys))
      in
      let m =
        match Random.State.int random 3 with
        | 1 when keys <> [] -> M.remove (some_key ()) m
        | 2 when keys <> [] -> M.add (some_key ()) (random_value ()) m
        | _ -> M.add (random_key ()) (random_value ()) m
      in
      change m (n - 1)
  in
  let random_pair i =
    let m1 = random_map (Random.State.int random 64) in
    let m2 =
      match i mod 10 with
      | 0 -> random_map (Random.State.int random 64)
      | 1 -> M.empty
      | _ -> change m1 (Random.State.int random 6)
    in
    if Random.State.bool random then m1, m2 else m2, m1
  in
  (* The result of a walk: bindings as [(key, left value, right value)].
     The keys bound in one map only give their binding. For the keys bound in
     both maps, [differing] keeps those bound to different values, and [all]
     keeps them all; with [all], [same] must give the bindings of the shared
     subtree. *)
  let only_left t = M.fold (fun k v acc -> (k, Some v, None) :: acc) t [] in
  let only_right t = M.fold (fun k v acc -> (k, None, Some v) :: acc) t [] in
  let differing k v1 v2 = if v1 = v2 then [] else [ k, Some v1, Some v2 ] in
  let all k v1 v2 = [ k, Some v1, Some v2 ] in
  let all_shared t = M.fold (fun k v acc -> (k, Some v, Some v) :: acc) t [] in
  let direct both m1 m2 =
    let left =
      M.fold
        (fun k v acc ->
           match M.find_check_missing k m2 with
           | v' -> both k v v' @ acc
           | exception Not_found -> (k, Some v, None) :: acc)
        m1 []
    in
    M.fold
      (fun k v acc -> if M.mem k m1 then acc else (k, None, Some v) :: acc)
      m2 left
  in
  let heterogeneous both =
    M.fold2_join_heterogeneous ~cache:Hptmap_sig.NoCache
      ~empty_left:only_right ~empty_right:only_left ~both
      ~join:( @ ) ~empty:[]
  in
  (* Calls of [both] on equal values, and of [same] on several keys. *)
  let both_equal = ref 0 and same_shared = ref 0 in
  let homogeneous ~cache both same =
    let both k v1 v2 = if v1 = v2 then incr both_equal; both k v1 v2 in
    M.fold2_join_homogeneous ~cache
      ~empty_left:only_right ~empty_right:only_left ~both ~same
      ~join:( @ ) ~empty:[]
  in
  let none_shared t = if M.cardinal t > 1 then incr same_shared; [] in
  let cache name = Hptmap_sig.TemporaryCache name in
  (* Each reference, with the walks whose results must equal it. *)
  let walks =
    [ direct differing,
      [ heterogeneous differing;
        homogeneous ~cache:Hptmap_sig.NoCache differing none_shared;
        homogeneous ~cache:(cache "test_hptmap_differing") differing
          (fun _ -> []) ];
      direct all,
      [ heterogeneous all;
        homogeneous ~cache:Hptmap_sig.NoCache all all_shared;
        homogeneous ~cache:(cache "test_hptmap_all") all all_shared ] ]
  in
  let check i =
    let m1, m2 = random_pair i in
    let same_result (reference, walks) =
      let expected = List.sort compare (reference m1 m2) in
      List.for_all (fun walk -> List.sort compare (walk m1 m2) = expected) walks
    in
    let ok = List.for_all same_result walks in
    if not ok then
      Format.eprintf "fold2_join_homogeneous: wrong result on@.%a@.and@.%a@."
        M.pretty m1 M.pretty m2;
    ok
  in
  let ok = List.for_all check (List.init 2000 Fun.id) in
  if !both_equal <> 0 || !same_shared = 0 then
    Format.eprintf "fold2_join_homogeneous: %d calls of both on equal values, \
                    %d calls of same on several keys@."
      !both_equal !same_shared;
  ok && !both_equal = 0 && !same_shared > 0
