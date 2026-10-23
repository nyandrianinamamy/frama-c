# We only perform some basic testing of Frama-Smith, by running it once and
# just checking that the JSON templates are up-to-date
# (e.g. no new command-line options).

  $ FRAMAC_TESTING=yes N_TRIES=0 SOURCES_GLOB="*.[ci]" ../../../dev/frama-smith.py
  <COUNT> fuzzable sources.
  Autocomplete filter: '@all'. Fuzzing <COUNT> Frama-C command-line options (0 option(s) not supported in current mode).
  *** Executions ended without error: 0/0 (0 timeouts)

We create a plugin that simply crashes and use it to test a script
  $ dune build --cache=disabled --root . @install

  $ dune exec --cache=disabled -- ../../../dev/minimize-crash-cmdline.py . foo.c -no-autoload-plugins
  [kernel] Parsing foo.c (with preprocessing)
  
  error: supplied command line did not crash (expected return code 4, got 0)!
  [1]

  $ dune exec --cache=disabled -- ../../../dev/minimize-crash-cmdline.py . foo.c -no-autoload-plugins -load-module crash.core
  iterating... (4 options remaining)
  iterating... (3 options remaining)
  iterating... (3 options remaining)
  iterating... (3 options remaining)
  Minimized command line: (cd . && frama-c "-no-autoload-plugins" "-load-module" "crash.core")

  $ FRAMAC_TESTING=yes N_TRIES=1 SOURCES_GLOB="*.[ci]" PRINT_UP_TO=6 dune exec --cache=disabled -- ../../../dev/frama-smith.py -no-autoload-plugins -load-module args_reader.core -cpp-extra-args="\"-I foo\"" | grep -v "running: frama-c"
  1: [foo.c]
  <COUNT> fuzzable sources.
  Autocomplete filter: '@all'. Fuzzing <COUNT> Frama-C command-line options (0 option(s) not supported in current mode).
  *** Generating command 1/1...
  2: [-cpp-extra-args=]
  3: [-no-autoload-plugins]
  4: [-load-module]
  5: [args_reader.core]
  6: [-cpp-extra-args="-I foo"]
  *** Executions ended without error: 1/1 (0 timeouts)
