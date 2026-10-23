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
