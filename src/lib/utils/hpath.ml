(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(* When testing this module, allow windows paths *)
let testing_mode = ref false

let%test_module _ = (module struct
  let () = testing_mode := true
end)


(* Special path handling *)
type absolute_path_kind =
  | WindowsUnparsed
  | WindowsDevice
  | WindowsDriveAbsolute of string (* drive letter *)
  | Network of string (* host name *)
  | FilesystemRoot

type relative_path_kind =
  | WindowsDriveRelative of string (* drive letter *)
  | CwdRelative

type path_kind =
  | Absolute of absolute_path_kind
  | Relative of relative_path_kind


(* --- Parsing --- *)

let re_special_paths, re_dir_separator =
  let win32 = Sys.win32 || !testing_mode in
  let slash = if win32 then "[\\\\/]" else "/" in
  let no_slash = if win32 then "[^\\\\/]" else "[^/]" in
  let (|^) l r = l ^ "\\|" ^ r in
  let group s = "\\(" ^  s ^ "\\)" in
  let alpha = "[A-Za-z]" in
  Str.regexp (
    "^" ^ group (slash ^ slash ^ "\\?" ^ slash) |^ (* \\?\path *)
    "^" ^ group (slash ^ slash ^ "\\." ^ slash) |^ (* \\.\path *)
    "^" ^ slash ^ slash ^ group (no_slash ^ "+") ^ slash |^ (* //host/path *)
    "^" ^ group alpha ^ ":" ^  slash |^ (* c:\path *)
    "^" ^ group alpha ^ ":" |^ (* c:path *)
    "^" ^ group slash (* /path *)
  ),
  Str.regexp slash

let parse_path s =
  let matched_group () =
    let rec aux i =
      try
        Str.group_beginning i |> ignore;
        i, lazy (Str.matched_group i s)
      with
      | Not_found -> aux (i + 1)
      | Invalid_argument _ -> -1, lazy ""
    in
    aux 1
  in
  let kind, rest =
    if not (Str.string_match re_special_paths s 0) then
      Relative CwdRelative, s
    else
      let kind = match matched_group () with
        | 1, _ -> Absolute WindowsUnparsed
        | 2, _ -> Absolute WindowsDevice
        | 3, hostname -> Absolute (Network (Lazy.force hostname))
        | 4, drive ->
          let drive = Lazy.force drive |> String.lowercase_ascii in
          Absolute (WindowsDriveAbsolute drive)
        | 5, drive ->
          let drive = Lazy.force drive |> String.lowercase_ascii in
          Relative (WindowsDriveRelative drive)
        | 6, _ -> Absolute FilesystemRoot
        | _ -> assert false
      in
      let pos = Str.match_end () in
      let rest = String.sub s pos (String.length s - pos) in
      kind, rest
  in
  kind, Str.split_delim re_dir_separator rest

let absolute_path_prefix = function
  | WindowsUnparsed -> "\\\\?\\"
  | WindowsDevice -> "\\\\.\\"
  | WindowsDriveAbsolute drive -> Printf.sprintf "%s:/" drive
  | Network hostname -> Printf.sprintf "//%s/" hostname
  | FilesystemRoot -> "/"


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
  let dummy =
    { path_name="";
      base_name="";
      parent=None;
      hash=0;
      symbolic_name=None;
    }
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
    | None ->
      base_name
    | Some { parent=None; path_name=parent_path } ->
      parent_path ^ base_name (* parent_path already contains "/" or "\\" *)
    | Some { parent=Some _; path_name=parent_path } ->
      Printf.sprintf "%s/%s" parent_path base_name
  in
  let hash = String.hash path_name in
  Hcons.merge
    { path_name;
      base_name;
      parent;
      hash;
      symbolic_name = None
    }


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

let parent_path path =
  match path.parent with
  | None -> path (* the parent of a root directory is itself *)
  | Some d -> d

let rec normalize ~parent = function
  | [] -> parent
  | "" :: ps -> normalize ~parent ps (* ignore empty parts *)
  | ".." :: ps -> normalize ~parent:(parent_path parent) ps
  | "." :: ps -> normalize ~parent ps
  | p :: ps -> normalize ~parent:(make ~parent p) ps

let insert ~base path_name =
  Cache.memo base path_name @@ fun () ->
  let path_kind, parts = parse_path path_name in
  let parent =
    match path_kind with
    | Relative (WindowsDriveRelative _)
    | Absolute (WindowsUnparsed | WindowsDevice) ->
      invalid_arg "unsupported windows relative or special path"
    | Relative CwdRelative ->
      assert (base != dummy);
      base
    | Absolute (WindowsDriveAbsolute _ | FilesystemRoot | Network _ as kind)->
      make (absolute_path_prefix kind)
  in
  normalize ~parent parts

let cwd = Unix.(realpath (getcwd ())) |> insert ~base:dummy


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
        if Buffer.length buffer > 0 && parent.parent != None then
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
  let pretty_paths fmt =
    let pp_path fmt p =
      Format.fprintf fmt "\n%S" p.path_name;
      match p.parent with
      | None -> Format.fprintf fmt " (root)"
      | Some p -> Format.fprintf fmt " -> %S" p.path_name
    in
    Hcons.iter (pp_path fmt)

  let test_paths ?base paths expected =
    Hcons.clear ();
    (* Insert paths in Hcons table *)
    List.iter (fun s -> of_string ?base s |> ignore) paths;
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
        {|C:\a/b/d|};
        {|d:\a\e|};
        {|/a/x/c|}; ]
      {|
"/" (root)
"/a" -> "/"
"/a/x" -> "/a"
"/a/x/c" -> "/a/x"
"c:/" (root)
"c:/a" -> "c:/"
"c:/a/b" -> "c:/a"
"c:/a/b/c" -> "c:/a/b"
"c:/a/b/d" -> "c:/a/b"
"d:/" (root)
"d:/a" -> "d:/"
"d:/a/e" -> "d:/a"|}

  let%test "relative directories" =
    test_paths ~base:"/root/subdir"
      [ {||};
        {|f|};
        {|../f|};
        {|./../g|};
        {|.././h|};
        {|i/../i/../j|} ]
      {|
"/" (root)
"/root" -> "/"
"/root/f" -> "/root"
"/root/g" -> "/root"
"/root/h" -> "/root"
"/root/subdir" -> "/root"
"/root/subdir/f" -> "/root/subdir"
"/root/subdir/i" -> "/root/subdir"
"/root/subdir/j" -> "/root/subdir"|}

  let%test "multiple slashes" =
    test_paths
      [ "//";
        "///";
        "//host//";
        "///tmp//dir///subdir//" ]
      {|
"/" (root)
"//host/" (root)
"/tmp" -> "/"
"/tmp/dir" -> "/tmp"
"/tmp/dir/subdir" -> "/tmp/dir"|}
end)
