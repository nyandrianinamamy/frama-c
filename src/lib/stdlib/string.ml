(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

include Stdlib.String

let compare_ignore_case s1 s2 =
  compare (lowercase_ascii s1) (lowercase_ascii s2)

let remove_prefix ?(strict=false) prefix s =
  if starts_with ~prefix s then
    let n = length s in
    let p = length prefix in
    if not strict || n > p then Some (sub s p (n-p)) else None
  else None

let remove_suffix ?(strict=false) suffix s =
  if ends_with ~suffix s then
    let n = length s in
    let p = length suffix in
    if not strict || n > p then Some (sub s 0 (n-p)) else None
  else None

let trim_underscores s =
  let l = length s in
  let rec start i =
    if i >= l then l
    else if get s i = '_' then start (i + 1) else i
  in
  let st = start 0 in
  if st = l then ""
  else begin
    let rec finish i =
      (* We know that we will stop at >= st >= 0 *)
      if get s i = '_' then finish (i - 1) else i
    in
    let fin = finish (l - 1) in
    sub s st (fin - st + 1)
  end

let utf8_length s =
  let rec aux i count =
    if i >= length s then count
    else
      let uchar = get_utf_8_uchar s i in
      let len = Uchar.utf_decode_length uchar in
      aux (i + len) (count + 1)
  in
  aux 0 0

let utf8_escaped s =
  let escape_char c =
    if c = '"' then "\\\"" else Char.escaped c
  in
  let buffer = Buffer.create (length s) in
  let rec aux i =
    if i < length s then
      let uchar = get_utf_8_uchar s i in
      let len = Uchar.utf_decode_length uchar in
      if len = 1
      then escape_char (get s i) |> Buffer.add_string buffer
      else Uchar.utf_decode_uchar uchar |> Buffer.add_utf_8_uchar buffer;
      aux (i + len)
  in
  aux 0;
  Buffer.contents buffer

let html_escape s =
  let buf = Buffer.create (length s) in
  iter
    (function
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '&' -> Buffer.add_string buf "&amp;"
      | c -> Buffer.add_char buf c
    ) s ;
  Buffer.contents buf

let percent_encode s =
  let buf = Buffer.create (length s) in
  iter
    (function
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
      | '-' | '.' | '_' | '~' as c ->
        Buffer.add_char buf c
      | c ->
        let code = Char.code c in
        let percent_code = Format.asprintf "%%%2X" code in
        Buffer.add_string buf percent_code)
    s;
  Buffer.contents buf

let means_yes s =
  match lowercase_ascii s with
  | "yes" | "true" | "1" -> true
  | _ -> false


(* --- Inline test --- *)

let%test "utf8_length" =
  let pangram = (* Spanish pangram *)
    "El veloz murciélago hindú comía feliz cardillo y kiwi. La cigüeña tocaba \
     el saxofón detrás del palenque de paja."
  in
  utf8_length pangram = 112

(* Features from OCaml 5.5 *)

(******************************************************************************)
(*                                                                            *)
(*                                   OCaml                                    *)
(*                                                                            *)
(*             Damien Doligez, projet Gallium, INRIA Rocquencourt             *)
(*                                                                            *)
(*  Copyright 2014 Institut National de Recherche en Informatique et          *)
(*                 en Automatique.                                            *)
(*                                                                            *)
(*  All rights reserved.  This file is distributed under the terms of the     *)
(*  GNU Lesser General Public License version 2.1, with the special           *)
(*  exception on linking described below. See the GNU Library General Public  *)
(*  License version 2 for more details (enclosed in the file                  *)
(*  licenses/LGPLv2).                                                         *)
(*  As a special exception to the GNU Library General Public License, you     *)
(*  may link, statically or dynamically, a "work that uses the Library" with  *)
(*  a publicly distributed version of the Library to produce an executable    *)
(*  file containing portions of the Library, and distribute that executable   *)
(*  file under terms of your choice, without any of the additional            *)
(*  requirements listed in clause 6 of the GNU Library General Public         *)
(*  License.                                                                  *)
(*  By "a publicly distributed version of the Library", we mean either the    *)
(*  unmodified Library as distributed by INRIA, or a modified version of the  *)
(*  Library that is distributed under the conditions defined in clause 2 of   *)
(*  the GNU Library General Public License. This exception does not however   *)
(*  invalidate any other reasons why the executable file might be covered by  *)
(*  the GNU Library General Public License.                                   *)
(*                                                                            *)
(******************************************************************************)

let invalid_start ~start len =
  let i = string_of_int in
  invalid_arg @@ concat "" ["start: "; i start; " not in range [0;"; i len; "]"]

module Search = struct
  (* Two way string search, see https://doi.org/10.1145/116825.116845 or
     http://www-igm.univ-mlv.fr/~lecroq/string/node26.html#SECTION00260 *)

  let find_maximal_suffix_and_period ~sub =
    let sublen = length sub in
    let i = ref (-1) and j = ref 0 and k = ref 1 and p = ref 1 in
    let[@inline] maximal_suffix ~order =
      while (!j + !k < sublen) do
        let c = order * Char.compare (get sub (!j + !k)) (get sub (!i + !k)) in
        if c < 0 then (j := !j + !k; k := 1; p := !j - !i) else
        if c > 0 then (i := !j; j := !i + 1; k := 1; p := 1) else
          (* c = 0 *)
        if !k = !p then (j := !j + !p; k := 1) else incr k
      done;
    in
    (maximal_suffix[@inlined]) ~order:1;
    let l0 = !i and p0 = !p in
    i := -1; j := 0; k := 1; p := 1;
    (maximal_suffix[@inlined]) ~order:(-1);
    let l1 = !i and p1 = !p in
    if l0 > l1 then (l0, p0) else (l1, p1)

  let is_sub_periodic ~sub ~sub_lp:(l, p) =
    l <= p &&
    let i = ref 0 in
    while !i <= l && Char.equal (get sub !i) (get sub (!i + p))
    do incr i done;
    !i > l

  let find ~start ~sub ~sub_lp:(l, p) ~sub_periodic s = (* -1 on not found *)
    let slen = length s and sublen = length sub in
    if not (0 <= start && start <= slen) then invalid_start ~start slen else
      let smax = slen - sublen in
      let j = ref start in
      try
        if sub_periodic then begin
          let memory = ref (-1) in
          while (!j <= smax) do
            let i = ref (1 + Int.max l !memory) in
            while (!i < sublen && Char.equal (get sub !i) (get s (!i + !j)))
            do incr i done;
            if !i < sublen then (j := !j + (!i - l); memory := -1) else
              begin
                i := l;
                while (!i > !memory && Char.equal (get sub !i) (get s (!i + !j)))
                do decr i done;
                if !i <= !memory then raise_notrace Exit else
                  (j := !j + p; memory := sublen - p - 1)
              end
          done;
          -1
        end else begin
          let q = 1 + Int.max (l + 1) (sublen - l - 1) in
          while (!j <= smax) do
            let i = ref (l + 1) in
            while (!i < sublen && Char.equal (get sub !i) (get s (!i + !j)))
            do incr i done;
            if !i < sublen then (j := !j + (!i - l)) else
              begin
                i := l;
                while (!i >= 0 && Char.equal (get sub !i) (get s (!i + !j)))
                do decr i done;
                if !i < 0 then raise_notrace Exit else (j := !j + q)
              end
          done;
          -1
        end
      with Exit -> !j
end

let find_first ~sub =
  let sub_lp = Search.find_maximal_suffix_and_period ~sub in
  let sub_periodic = Search.is_sub_periodic ~sub ~sub_lp in
  fun ?(start = 0) s ->
    match Search.find ~start ~sub ~sub_lp ~sub_periodic s with
    | -1 -> None | i -> Some i
