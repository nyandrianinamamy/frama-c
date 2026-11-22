The hit log observer analyses its reference without memexec, and observes
the programs of the tests of Eva only. It refuses a program whose sources,
once their symbolic links are resolved, are outside plugins/eva/tests and
the share directories of Frama-C, or cannot be resolved; it finds the
sources in the AST and in File.get_all, whichever way the AST was built
(check_sources in plugins/eva/tests/hit_log/hit_log_observer.ml).

Compilation of the observer, and of init_files.ml, which builds the AST with
File.init_from_c_files, with no file on the command line.
  $ cp ../../hit_log/hit_log_observer.ml .
  $ dune build --cache=disabled --root . ./hit_log_observer.cmxs ./init_files.cmxs
  $ OBSERVER=$PWD/_build/default/hit_log_observer.cmxs
  $ INIT=$PWD/_build/default/init_files.cmxs
  $ OPTIONS="-no-autoload-plugins -load-plugin=eva,inout -machdep x86_32 -eva-verbose 0 -eva-hit-log"

A directory outside the tests of Eva, with a program and a header.
  $ OUT=$(mktemp -d)
  $ case "$(realpath "$OUT")" in */plugins/eva/tests/*) echo inside;; *) echo outside;; esac
  outside
  $ cat > "$OUT/ext.c" <<EOF
  > int g;
  > int main(void) { g = 1; return g; }
  > EOF
  $ cat > "$OUT/ext.h" <<EOF
  > int from_outside;
  > EOF

Refused: the program, on the command line.
  $ frama-c $OPTIONS -load-module "$OBSERVER" "$OUT/ext.c" > outside.log 2>&1
  [1]
  $ sed "s|$OUT|OUT|g" outside.log
  [kernel] Parsing OUT/ext.c (with preprocessing)
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; these source files are outside plugins/eva/tests and the share directories of Frama-C: OUT/ext.c. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Refused: the program, through File.init_from_c_files; Kernel.Files is empty.
  $ HIT_LOG_GUARD_INIT="$OUT/ext.c" frama-c $OPTIONS -load-module "$INIT,$OBSERVER" > init.log 2>&1
  [1]
  $ sed "s|$OUT|OUT|g" init.log
  [kernel] Parsing OUT/ext.c (with preprocessing)
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; these source files are outside plugins/eva/tests and the share directories of Frama-C: OUT/ext.c. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Refused: the program, through File.init_from_c_files, in a project saved
then loaded with -load.
  $ HIT_LOG_GUARD_INIT="$OUT/ext.c" frama-c $OPTIONS -load-module "$INIT" -save init.sav > init-save.log 2>&1
  $ frama-c $OPTIONS -load init.sav -load-module "$OBSERVER" > init-load.log 2>&1
  [1]
  $ sed "s|$OUT|OUT|g" init-load.log
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; these source files are outside plugins/eva/tests and the share directories of Frama-C: OUT/ext.c. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Refused: an AST with a global and no source file: the empty AST of no file,
to which init_files.ml adds a global with a generated location.
  $ HIT_LOG_GUARD_SYNTHETIC=1 frama-c $OPTIONS -load-module "$INIT,$OBSERVER" > synthetic.log 2>&1
  [1]
  $ cat synthetic.log
  [kernel] Warning: no input file.
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; the AST has globals but no source file. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Refused: the program, through a symbolic link in the tests, on the command
line.
  $ ln -s "$OUT/ext.c" link.c
  $ frama-c $OPTIONS -load-module "$OBSERVER" link.c > link.log 2>&1
  [1]
  $ sed "s|$OUT|OUT|g" link.log
  [kernel] Parsing link.c (with preprocessing)
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; these source files are outside plugins/eva/tests and the share directories of Frama-C: $TESTCASE_ROOT/link.c. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Refused: the header, through a symbolic link in the tests, included by a
program of the tests.
  $ ln -s "$OUT/ext.h" linked.h
  $ frama-c $OPTIONS -load-module "$OBSERVER" inc.c > linked.log 2>&1
  [1]
  $ sed "s|$OUT|OUT|g" linked.log
  [kernel] Parsing inc.c (with preprocessing)
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; these source files are outside plugins/eva/tests and the share directories of Frama-C: $TESTCASE_ROOT/linked.h. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Refused: the program, named through a symbolic link in the tests that no
longer exists, in a project saved then loaded with -load.
  $ ln -s "$OUT/ext.c" gone.c
  $ frama-c $OPTIONS gone.c -save gone.sav > gone-save.log 2>&1
  $ rm gone.c
  $ frama-c $OPTIONS -load gone.sav -load-module "$OBSERVER" > gone.log 2>&1
  [1]
  $ sed "s|$OUT|OUT|g" gone.log
  [kernel] User Error: the hit log observer analyses its reference without memexec, and observes the tests of Eva only; these source paths are unresolvable: $TESTCASE_ROOT/gone.c. Set HIT_LOG_OBSERVER_ANY_PROGRAM=1 to observe the program anyway.
  [kernel] Frama-C aborted: invalid user input.

Accepted: a program of the tests, through a symbolic link from a directory
outside the tests, as dev/hit-log-suite.py runs it.
  $ mkdir "$OUT/work"
  $ ln -s "$PWD/prog.c" "$OUT/work/prog.c"
  $ (cd "$OUT/work" && frama-c $OPTIONS -load-module "$OBSERVER" prog.c) > work.log 2>&1
  $ grep "^Initial state" work.log
  Initial state: equal.

Accepted: a program of the tests with a file of the share directory, on the
command line. In the install layout of Dune, that file is a symbolic link
into the build tree.
  $ SHARE=$(frama-c -print-share-path)
  $ test -L "$SHARE/libc/__fc_builtin.c" && echo "symbolic link"
  symbolic link
  $ frama-c $OPTIONS -load-module "$OBSERVER" prog.c "$SHARE/libc/__fc_builtin.c" > share.log 2>&1
  $ grep "^Initial state" share.log
  Initial state: equal.

  $ rm -rf "$OUT"
