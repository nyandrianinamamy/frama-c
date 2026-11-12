Test quoting of options for lists, (multi-)maps and filepaths

Compile the helper test module
  $ dune build --cache=disabled --root . @install

Run frama-c with only the helper test module
  $ alias frama-c="dune exec --cache=disabled -- frama-c \
  > -no-autoload-plugins \
  > -load-module quoted_parameters"

Test option kinds with different quoting, and save the result in session.sav
  $ frama-c \
  > -qp-map='"k_abc:def\":ghi":v_jkl' \
  > -qp-map="\"k_lmn:'opq\\\":rst\":v_uvw" \
  > -qp-multi-map "\"k_a:b\":v1_c::d:\"v2_e':\\\"f\":v3_g" \
  > -qp-multi-map "\"k_h:i\":v1_j::k:'v2_l\\':\"m':v3_n" \
  > -qp-filepath-linux /path/to/arbitrary/file.txt \
  > -qp-filepath-windows c:\\path\\to\\arbitrary\\file.txt \
  > -qp-filepath-with-space "c:/path with space/to/file.txt" \
  > -qp-filepath-list "/linux/path/file.txt,c:\\windows\\path\\file.txt" \
  > -qp-filepath-list "c:/path with space/file.txt,/path/with\\,comma/file.txt" \
  > -qp-filepath-map "/linux/path/file.txt:linux,'c:\\\\\\\\windows\\\\\\\\path':windows" \
  > -qp-filepath-map "/path/with\\,comma:comma" \
  > -qp-filepath-map "/linux/with space:linux space" \
  > -qp-filepath-map "'c:/windows/with space':windows space" \
  > -qp-filepath-map "/with space/and\\,comma:space and comma" \
  > -save session.sav > output.log

  $ cat output.log
  [qp] map:
    {{ "k_abc:def\":ghi" -> "v_jkl"; "k_lmn:'opq\":rst" -> "v_uvw" }}
  [qp] multi-map:
    {{ "k_a:b" -> [ "v1_c::d"; "v2_e':\"f"; "v3_g" ];
       "k_h:i" -> [ "v1_j::k"; "v2_l':\"m"; "v3_n" ] }}
  [qp] filepath linux:
      /path/to/arbitrary/file.txt
  [qp] filepath windows:
      c:/path/to/arbitrary/file.txt
  [qp] filepath with space:
      c:/path with space/to/file.txt
  [qp] filepath list:
      [ /linux/path/file.txt;
        c:/windows/path/file.txt;
        c:/path with space/file.txt;
        /path/with,comma/file.txt ]
  [qp] filepath map:
      {{ /linux/path/file.txt -> "linux";
         /linux/with space -> "linux space";
         /path/with,comma -> "comma";
         /with space/and,comma -> "space and comma";
         c:/windows/path -> "windows";
         c:/windows/with space -> "windows space" }}

Reload session.sav to check that the options have the same values
  $ frama-c -load session.sav > output_saved_session.log
  $ diff -u output.log output_saved_session.log
