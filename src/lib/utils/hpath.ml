(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* re_drive match drive expressions to deal with non-Cygwin Windows-like paths
   (e.g. with MinGW) *)
let re_drive = Str.regexp {|[A-Za-z]:|}
let re_dir_separator = Str.regexp {|[/\\]|}


(* --- Type definition --- *)

module Prototype = struct
  type t = {
    path_name : string ;
    base_name : string ; (* Filename.basename *)
    parent : t option ; (* path whose path_name is Filename.dirname *)
    hash : int ;
    mutable symbolic_name : string option; (* Symbolic name *)
  }
  let hash p = p.hash
  let equal p q = p.path_name = q.path_name
end

include Prototype

module Table = Hashtbl.Make (Prototype)

(** Hashconsing table for [Hpath.t].
    It ensures that [==] can be used to test equality between them. *)
module Hcons : sig
  val merge : t -> t
  val clear : unit -> unit
  val iter : (t -> unit) -> unit
end =
struct
  (** Cannot use {!Weak}, since the internal [t] representation is temporary.
      Cannot use a weak-cache because each minor GC may empty the cache
      (see #191). *)
  let table : t Table.t = Table.create 128
  let merge p = Table.memo table p (fun _ -> p)
  let clear () = Table.clear table
  let iter f =
    let cmp p1 p2 = String.compare p1.path_name p2.path_name in
    Table.iter_sorted_by_value ~cmp (fun _ p -> f p) table
end


(* --- Construction --- *)

let make ?parent base_name =
  let path_name = match parent with
    | None -> base_name
    | Some parent ->  Printf.sprintf "%s/%s" parent.path_name base_name
  in
  let hash = String.hash path_name in
  Hcons.merge
    { path_name;
      base_name;
      parent;
      hash;
      symbolic_name = None
    }

let empty = make ""


(* --- Normalization --- *)

(** Cache using a hash table from unnormalized paths to normalized paths. *)
module Cache : sig
  val memo : t -> string -> (unit -> t) -> t
end =
struct
  (* Until Hashtbl.memo is implemented in stdlib's Hashtbl, we store the hash
     with the key to prevent computing the hash twice. *)
  module Key = struct
    type t = { base: Prototype.t; file_path: string; hash: int }

    let make base file_path =
      let hash = Hashtbl.hash (String.hash file_path, Prototype.hash base) in
      { base; file_path; hash }

    let equal k1 k2 =
      k1.base == k2.base &&
      String.equal k1.file_path k2.file_path

    let hash k = k.hash
  end

  module Table = Hashtbl.Make (Key)

  let table : t Table.t = Table.create 256

  let memo base file_path f =
    let key = Key.make base file_path in
    Table.memo table key (fun _ -> f ())
end

let parent path =
  match path.parent with
  | None -> path (* the parent of the root directory is itself *)
  | Some d -> d

let rec normalize parent_path = function
  | [] | [""] -> parent_path
  | ".." :: ps -> normalize (parent parent_path) ps
  | "." :: ps -> normalize parent_path ps
  | p :: ps -> normalize (make ~parent:parent_path p) ps

let insert ?(base=empty) path_name =
  Cache.memo base path_name @@ fun () ->
  match Str.split_delim re_dir_separator path_name with
  | "" :: parts ->
    normalize empty parts
  | p :: parts when Str.string_match re_drive p 0 ->
    let p = String.lowercase_ascii p in (* Normalize windows drive letter *)
    normalize (make p) parts
  | parts ->
    normalize base parts

let cwd = Unix.(realpath (getcwd ())) |> insert


(* --- Conversion --- *)

let of_string ?base path_name =
  let base = Option.fold ~none:cwd ~some:(insert ~base:cwd) base in
  insert ~base path_name

let to_string path =
  path.path_name

type base = Absolute | Cwd | Name of string * t

let to_uri path =
  let buffer = Buffer.create 80 in
  let rec add_component path =
    match path.symbolic_name with
    | Some sn -> Name (sn, path)
    | None when path == cwd (* hconsed *) -> Cwd
    | None ->
      match path.parent with
      | None -> (* root *)
        Buffer.add_string buffer path.path_name;
        Absolute
      | Some parent ->
        let base = add_component parent in
        if Buffer.length buffer > 0 || base = Absolute then
          Buffer.add_char buffer '/';
        Buffer.add_string buffer path.base_name;
        base
  in
  let base = add_component path in
  let uri = Buffer.contents buffer in
  base, uri


(* -------------------------------------------------------------------------- *)
(* --- Symbolic Names                                                     --- *)
(* -------------------------------------------------------------------------- *)

(* Note: Symbolic directories are not currently projectified *)

module Names = struct
  let table : string Table.t = Table.create 3

  let add path name =
    Table.replace table path name;
    path.symbolic_name <- Some name

  let remove path =
    Table.remove table path;
    path.symbolic_name <- None

  let all () =
    let compare (p1, n1) (p2, n2) =
      let c = String.compare n1 n2 in
      if c <> 0 then c
      else String.compare p1.path_name p2.path_name
    in
    Table.to_seq table
    |> List.of_seq
    |> List.sort compare
end


(* -------------------------------------------------------------------------- *)
(* --- Testing                                                            --- *)
(* -------------------------------------------------------------------------- *)

let%test_module _ = (module struct
  let reset_tables () =
    Hcons.clear ();
    Hcons.merge empty |> ignore

  let pretty_paths fmt =
    let pp_path fmt p =
      Format.fprintf fmt "\n%S" p.path_name;
      match p.parent with
      | None -> Format.fprintf fmt " (root)"
      | Some p -> Format.fprintf fmt " -> %S" p.path_name
    in
    Hcons.iter (pp_path fmt)

  let test_paths paths expected =
    reset_tables ();
    (* Insert paths in Hcons table *)
    List.iter (fun s -> insert s |> ignore) paths;
    (* Print and compare the result *)
    let actual = Format.asprintf "%t" pretty_paths in
    let success = String.equal actual expected in
    if not success then
      Format.eprintf "Test failed.\nActual:\n%s\nExpected:\n%s\n"
        actual expected;
    success

  let%test "absolute directories" =
    test_paths
      [ {|c:\a\b\c|};
        {|C:/a/b/d|};
        {|/a/x/c|}; ]
      {|
"" (root)
"/a" -> ""
"/a/x" -> "/a"
"/a/x/c" -> "/a/x"
"c:" (root)
"c:/a" -> "c:"
"c:/a/b" -> "c:/a"
"c:/a/b/c" -> "c:/a/b"
"c:/a/b/d" -> "c:/a/b"|}
end)
