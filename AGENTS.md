## Agent skills

### Issue tracker

Issues live in GitHub Issues on `nyandrianinamamy/frama-c` (the `origin` remote), via the `gh` CLI. Never file into the `upstream` GitLab project. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.


## Working in this checkout

This file is the repository-wide entry point for coding-agent instructions.
Automatic loading depends on the harness, including for Claude-based agents;
read this file explicitly if it was not loaded. Before editing a subtree,
check for and read any nested `AGENTS.md` yourself rather than assuming the
harness loads it. Preserve unrelated working-tree changes. The issue routing
above overrides the upstream GitLab workflow in `CONTRIBUTING.md`.

- Kernel and shared OCaml libraries: `src/kernel/`, `src/lib/`.
- Eva: `plugins/eva/src/` (engine, domains, public interfaces), with regression
  suites in `plugins/eva/tests/`. Kernel regression suites live in `tests/`.
- For OCaml contributions, read [CONTRIBUTING.md](CONTRIBUTING.md#coding-conventions).
  For GUI changes, use [ivette/CONTRIBUTING.md](ivette/CONTRIBUTING.md) and
  [ivette/tests/README.md](ivette/tests/README.md); the commands below concern
  the OCaml analyzer and its tests.

## Build and prerequisites

Run commands from the repository root. Once the local switch exists, activate
it with `eval "$(opam env --switch=. --set-switch)"` before building, then check
`ocamlc -version` and `dune --version`. The current [opam](opam) requires
OCaml >= 5.2.0 and Dune > 3.15.0; use its dependency constraints rather than
assuming the system compiler or another checkout's switch is suitable.
For initial setup, see [INSTALL.md](INSTALL.md#full-compilation-guide).
On Ubuntu 24.04, use a **local** switch so other checkouts keep their compilers:

```sh
# System dependencies (requires sudo; installs packages, not a system upgrade).
sudo apt-get install -y --no-install-recommends build-essential autoconf m4 \
  pkg-config git curl unzip patch libgmp-dev libmpfr-dev zlib1g-dev \
  graphviz time clang yq socat dos2unix libzmq3-dev \
  python3-venv jq cmake libclang-cpp-dev libclang-dev llvm-dev
opam update
opam switch create . ocaml-base-compiler.5.2.1 --no-install -y --jobs=8
eval "$(opam env --switch=. --set-switch)"
opam install --switch=. dune.3.21.1 -y --jobs=8
opam pin add --switch=. dune 3.21.1 --no-action -y
opam install --switch=. --deps-only --with-test . -y --jobs=8
DUNE_ROOT=. opam install --switch=. -y --jobs=8 apron zmq ocp-indent.1.10.0 \
  headache camomile alt-ergo.2.6.4 mopsa.1.2
```

`--no-install` defers the repository packages, not the compiler. Setup fetches
and builds packages. Do not rely on an inherited `OPAM_SWITCH_PREFIX` from
another checkout. Python test tools can be isolated inside the ignored switch
directory:

```sh
python3 -m venv _opam/setup-venv
_opam/setup-venv/bin/pip install check-jsonschema==0.39.0 PyYAML==6.0.3 \
  black==26.10.1 clang-format==21.1.8
```

Some agent harnesses start a fresh shell for every command. In each such call,
run both lines below in the same shell as the build, lint, or test command:

```sh
eval "$(opam env --switch=. --set-switch)"
export PATH="$PWD/_opam/setup-venv/bin:$PATH"
```

Keep this Python-tool path when running configuration and tests. PyYAML is
required by `share/machdeps/make_machdep/make_machdep.py`; adding a venv to
PATH means its Python also needs this dependency. Apron enables
additional Eva domains; ZeroMQ enables server support. `mopsa` supplies the
integration-test tools and needs the LLVM development packages above.
`headache`, `camomile` and `ocp-indent` support developer checks; Alt-Ergo
2.6.4 matches the development dependency in `opam`. Mopsa 1.2 constrains Dune
to < 3.22; installing Dune 3.21.1 first avoids rebuilding its dependents.
Use Dune 3.21.1 and keep it pinned in the switch; check `dune --version`
before running tests. With Dune 3.25.0, `tests/fc_script/estimate-difficulty.t`
fails: the script starts `frama-c` through
`_build/install/default/.packages/<hash>/bin/frama-c`, which exits at startup
with `Failure("hd")` because it does not find its share directory. If the
switch has another version, run
`DUNE_ROOT=. opam install --switch=. dune.3.21.1 -y --jobs=8`, which
recompiles the packages that depend on Dune, then pin the version with
`opam pin add --switch=. dune 3.21.1 --no-action -y`.
`DUNE_ROOT=.` keeps Mopsa's nested `make install` in its own package directory:
without it, an earlier attempt with Mopsa 1.1 selected the enclosing
Frama-C workspace and failed. Keep this variable scoped to that opam command.

```sh
dune build -j 8 @frama-c-configure   # inspect available plugins/test prerequisites
dune build -j 8 @install            # development build, including available plugins
dune exec -- frama-c -plugins       # confirm Eva is actually loaded
```

`make` wraps `dune build @install`; `make RELEASE=yes` uses the release profile
([Makefile](Makefile), [share/Makefile.common](share/Makefile.common)). No install
is needed for `dune exec`. For an Eva-only compilation check,
`dune build -j 8 plugins/eva/src/eva.cmxs` targets its core library and
transitive dependencies (target inferred from [plugins/eva/src/dune](plugins/eva/src/dune));
use `@install` before integration tests to include plugin/site artifacts.
Eva and its Apron extension are optional Dune libraries: a successful broad
build alone does not prove they were enabled. Read the configuration output;
Apron domain tests need the optional `apron` dependency. Test prerequisites
are defined in [tests_configurator.ml](tests_configurator.ml), including GCC
and Graphviz `dot` for Eva.

## OCaml style and checks

Use the surrounding module's conventions: paired `.ml`/`.mli` interfaces,
`(** ... *)` API documentation, and existing abstractions. Examples:
[compute_functions.ml](plugins/eva/src/engine/compute_functions.ml) and
[compute_functions.mli](plugins/eva/src/engine/compute_functions.mli).
Follow `ocp-indent` 1.10.0 and [.ocp-indent](.ocp-indent), avoid tabs/trailing
whitespace, and aim for 80 columns (contributor guide). This checkout uses
`ocp-indent`, not an assumed `ocamlformat` workflow.

- `git diff --check`: quick whitespace check for the patch.
- `make check-lint`: tracked-file checks selected by [.gitattributes](.gitattributes).
  See [tools/lint/README.md](tools/lint/README.md) and
  [tools/lint/frama-c-lint.opam](tools/lint/frama-c-lint.opam) for tool dependencies.
  Python/C formatting requires Black 26.x and clang-format 19–22 according to
  [tools/lint/lint.ml](tools/lint/lint.ml); Ubuntu 24.04 defaults are too old.
  Use `make check-lint LINTCK_EXTRA=-s` to fail on unavailable formatters.
  Checks run where attributes enable them;
  regression C files generally have indentation checks disabled.
- To limit linting to a tracked file, preserving its attributes:
  `git ls-files -z -- plugins/eva/src/engine/compute_functions.ml | git check-attr --stdin -z -a | dune exec --root tools/lint -- frama-c-lint`.
- `make check-headers`: license checks; requires the header checker dependencies,
  including `headache` ([share/Makefile.headers](share/Makefile.headers)).

`make lint` and `make headers` rewrite files across the selected scope; inspect
the diff and avoid unrelated rewrites. Follow existing Dune warning flags
rather than suppressing warnings to get a build through.

## Focused tests, then broader checks

**ptests prepares rules; Dune executes them.** Regenerate after adding tests or
changing `run.config`/`test_config`. The generation step writes Dune rules and
`.wtests` metadata under test directories; it does not establish a test pass.

```sh
# Generate Eva rules without purging every plugin's generated rules.
dune exec -- frama-c-ptests plugins/eva/tests
# One existing test, default configuration:
dune build -j 8 @plugins/eva/tests/value/result/abs.diff
# One suite, then all default Eva ptests:
dune build -j 8 @plugins/eva/tests/value/ptests_config
dune build -j 8 @plugins/eva/tests/ptests_config
# Eva's non-ptests tests (including cram):
dune runtest -j 8 plugins/eva
# A named domain configuration; use the one relevant to the change:
dune build -j 8 @plugins/eva/tests/ptests_config_octagon
```

The repository helper also supports a focused run:
`bash dev/test.sh -p -v plugins/eva/tests/value/abs.i -- -j 8`.
Here `-p` purges and regenerates rules repository-wide via `make run-ptests`,
although execution selects one file. Without `-p`, the helper can still do this
when its generated rules are missing or stale relative to the selected tests.
See [dev/test.sh](dev/test.sh): `-c NAME` selects a configuration, `-a` selects
all, `-l` displays a file's output, and `-f` forces reruns (also purging and
regenerating rules). `-u` and `-g` **auto-promote oracles**; omit them during
investigation.

Broader checks ([share/Makefile.testing](share/Makefile.testing)):

- `make default-tests`: regenerate all ptests, run `@ptests_config` and
  `dune runtest tests`. This is not all configurations or all inline tests.
- `make tests`: regenerate and run the Makefile's ptests aliases across all
  configurations; WP tests may require `FRAMAC_WP_CACHEDIR` and provers.
- After `make run-ptests`, `dune build -j 8 @runtest @ptests` combines native
  Dune tests and all ptests configurations; this is a broad, potentially costly run.

The Makefile test targets above do not pass `-j`; Dune chooses its own job
count. To enforce the eight-job default, prepare with `make run-ptests` and
use explicit Dune commands. For the `make default-tests` test scope, run
`dune build -j 8 @ptests_config` followed by `dune runtest -j 8 tests`.

CI evidence: [.gitlab-ci.yml](.gitlab-ci.yml), [nix/eva-tests.nix](nix/eva-tests.nix),
[nix/kernel-tests.nix](nix/kernel-tests.nix), and [nix/full-tests.nix](nix/full-tests.nix).
The Nix CI jobs prepare rules with `-never-disabled` so missing dependencies
fail rather than silently disabling tests; other CI jobs may omit this flag.
Ordinary local rules can skip unavailable plugins/dependencies; inspect
configuration and executed targets before claiming coverage. A cached or empty alias is not evidence of a fresh run.
For native/cram checks in a noninteractive agent shell, use `TERM=xterm`
(e.g. `TERM=xterm dune build -j 8 @runtest @ptests_config`). With `TERM` unset,
empty, or `dumb`, `tests/misc/log-truncation.t` fails because
`src/lib/utils/ansi_escape.ml` disables terminal support, so even its
pseudo-terminal output is not truncated.
Dune 3.21.1 reused cached cram outputs after Python/TERM changes even with
`--force`. For these setup fixes, remove only the affected generated directories
(`_build/default/tests/misc/.cram.log-truncation.t` and
`_build/default/tests/fc_script/.cram.make-machdep.t`), then run
`TERM=xterm dune runtest -j 8 --cache=disabled tests/misc tests/fc_script`.
Do not delete source `.t` directories or promote their stale differences.

## Test configurations and oracle investigation

Read the testing sections in [doc/developer/advance.tex](doc/developer/advance.tex)
and the worked example in [doc/developer/tutorial.tex](doc/developer/tutorial.tex)
when adding tests or changing expected results. The current generator's
[tools/ptests/ptests.ml](tools/ptests/ptests.ml) is authoritative for aliases
and directives where older manual examples differ.

- `ptests_config` lists suites/configurations; `test_config` and suite-local
  overrides supply inherited directives. `test_config_NAME` and
  `run.config_NAME` select named variants; `run.config*` applies to existing
  configurations. See [Eva's configuration](plugins/eva/tests/ptests_config).
- `OPT` defines a command's options; `STDOPT` adjusts inherited options.
  Declare auxiliary inputs using `DEPS` or Dune `%{dep:...}` references, and
  plugins with `PLUGIN`. Example:
  [assigns_from_direct.i](plugins/eva/tests/value/assigns_from_direct.i).
- Expected output is tracked under `oracle/` or `oracle_NAME/`, commonly
  `NAME.0.res.oracle` and `NAME.0.err.oracle`. Actual `.res.log`/`.err.log`
  files live under `_build/default/.../result[_NAME]/`. Check `FILTER` before
  interpreting a diff: [test_config_octagon](plugins/eva/tests/test_config_octagon)
  compares domain output against the default run's output.
- For the focused example above, inspect the generated `result/dune` and
  `.wtests` metadata, or run
  `dune build @plugins/eva/tests/value/result/abs.0.exec.show` to show the
  command and `dune build @plugins/eva/tests/value/result/abs.diff` for diffs.
  Reproduce with the same options, dependencies and working directory.
- Update expectations only after explaining why the behavioral change is
  correct. For a new test, use `frama-c-ptests -create-missing-oracles` through
  `dune exec --`, scoped to its test root, then run and inspect the test.
  Use `dune promote path/to/the/reviewed.oracle` for selected results; bare
  `dune promote` can accept unrelated pending differences. Rerun the focused
  tests and inspect `git diff` afterward. The generator's
  `-remove-empty-oracles` option cleans empty oracles in the selected scope.

## Verification and reporting

Choose checks by impact: documentation-only edits need link/content and
whitespace checks; OCaml edits need compilation and relevant regressions;
Eva transfer/domain changes need the affected cases, default Eva tests and
relevant domain configurations. Shared kernel/API changes warrant dependent
plugin tests and broader checks. Use eight jobs by default for builds, opam
installs, and tests (`-j 8` / `--jobs=8`). Add a suitable `timeout` when needed
and expand verification only as justified. If a command exceeds the harness's
foreground duration limit, use its supported persistent or background command
execution, retaining the timeout, logs, and exit status. Wait for completion
before reporting the result.

Report exact commands, scope/configuration, results and skipped checks.
Separate compiler/dependency failures, oracle mismatches, disabled tests,
timeouts and process kills; preserve diagnostics before retrying. Never turn
an unexplained failure into a pass by promoting outputs or disabling tests.

### Reviewing Lean–Eva correspondence

When reviewing a change to the Lean model or to Eva, check whether it affects
any claim in the correspondence record, including assumptions the claim relies
on. For each affected claim, the author identifies it in the PR, revisits its
argument, and reruns the proofs or regressions whose evidence the change
affects. Report the checked revision, results, and any checks still pending.
Update the record in the same change if the claim, argument, assumptions, or
source and test references have changed. The reviewer checks that assessment
and the cited evidence before signing off.

The Lean model is in `lean/`. Build and check it with
`cd lean && lake build --wfail`; [lean/README.md](lean/README.md) gives its
scope and pins. The Frama-C build does not need Lean. The correspondence record
is in [docs/eva/reuse-correspondence/](docs/eva/reuse-correspondence/README.md).

### Definition of done

For a feature or bug fix, confirm the observable acceptance criteria in the
ticket before implementation. Deliver a small, replayable acceptance demo:
the reviewer should be able to verify the behavior without reading the diff.

- For each criterion, report expected behavior, observed behavior, and
  `PASS`, `FAIL`, or `NOT RUN`. Include the tested revision, inputs and
  configuration, a single reproduction command or entry point, and the
  relevant output or log. Explain failures and skipped or blocked checks.
- Show that the changed path actually ran. For example, matching Eva outputs
  with caching on and off do not establish reuse unless the run records a
  cache hit. For a bug fix, show the reproducer failing before and passing
  after, when feasible.
- For work with a Lean proof, show the exact checked theorem statement, its
  hypotheses, and the `#print axioms` output. Flag any reliance on
  `sorryAx` or custom axioms. Report the OCaml obligations and their evidence
  separately; checking the Lean theorem does not establish that Eva meets
  its hypotheses.

Do not mark the ticket done if a required criterion failed or was not run.
Have the reviewer replay the demo or check the recorded CI evidence.

Setup verification (2026-11-17, source commit `0372456831`): local OCaml 5.2.1,
Dune 3.21.1, Why3 1.8.2, Alt-Ergo 2.6.4, Apron v0.9.15, Mopsa 1.2.
The Ubuntu 24.04 recipe above consolidates the installation steps (some base
packages were already present); the Dune pin avoids the dependency rebuild
encountered during setup. Full `@install`, plugin listing, strict lint across
11,583 files, header checks, and the focused `abs.diff` regression passed.
The following checks also passed (historical runs used two jobs; the current
default is eight jobs):

- `timeout 900 dune build -j 2 @plugins/eva/tests/ptests_config`.
- `timeout 300 dune runtest -j 2 plugins/eva`.
- `TERM=xterm timeout 900 dune build -j 2 @plugins/eva/tests/ptests` (all Eva
  configurations, including Apron).
- `TERM=xterm timeout 1200 dune build -j 2 @runtest @ptests_config`.

The first broad run failed on missing PyYAML and `TERM=dumb`; the two affected
native suites passed a fresh cache-disabled rerun after setup corrections.
The successful broad recheck reused the other results from the first run.

The configuration probe reports two platform limitations: Ubuntu's Graphviz
2.43 supports `dot -V`, but the probe uses `dot --version`; GCC 13.3 lacks
`-std=c2y`. Thus configuration summaries alone report disabled Eva/syntax
coverage even with executables present. Generate regression rules with
the Nix CI command
`dune exec -- frama-c-ptests -never-disabled tests plugins/*/tests`,
and inspect actual test outcomes. This does not enable conditionally disabled
native Dune/cram tests. Fuzzing, WP `qualif`, and GUI/browser checks were not
run. For those separate workflows, see [tests/fuzzing/README.md](tests/fuzzing/README.md)
(Crowbar and `FC_FUZZING`), [plugins/wp/tests/README.md](plugins/wp/tests/README.md)
(provers/cache; use the current `dev/test.sh` options), and the Ivette links above.

No oracles were promoted. Setup/build/check logs and the installed opam package
manifest/export are retained locally in `/tmp/frama-c-setup-2026-11-17/`
(ephemeral, not repository inputs).
