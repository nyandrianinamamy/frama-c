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

Run commands from the repository root. Some agent harnesses start a fresh
shell for every command. In each such call, run both lines below in the same
shell as the build, lint, test or `git commit` command:

```sh
eval "$(opam env --switch=. --set-switch)"
export PATH="$PWD/_opam/setup-venv/bin:$PATH"
```

In a git worktree, which has no switch of its own, replace `.` and `$PWD` with
the path of the main checkout. Create worktrees under `~/.t3/worktrees` or
beside the main checkout.

`bash dev/check-env.sh` checks that the active OCaml and Dune are the versions
this checkout is tested with; `dev/test.sh` runs it first. Run it before the
first build or test of a session. To create the switch, or to repair it when
the check fails, follow [docs/agents/setup.md](docs/agents/setup.md).


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

The git hooks in `dev/git-hooks/` run the lint and header checks on the files
of each commit and push, and `dev/check-cram-pipes.sh` on each commit. Install
them once per clone with `bash dev/git.sh hooks`. They need the two activation
lines above in the shell that runs `git commit` or `git push`.

In a cram test, redirect the output of `frama-c` to a file and inspect the
file in the next command, so that the test records the exit status. A pipe
such as `frama-c ... | grep` keeps the status of `grep` only;
`dev/check-cram-pipes.sh` rejects it in added lines.

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

`bash dev/verify.sh` runs the checks of an Eva change in one command and prints
one line per step with its exit status: build, default ptests of all plug-ins,
all Eva configurations, native tests of Eva and of the kernel, headers, and
lint on the files changed since a base revision (`-b REV`, default
`origin/dev`). It forces ptests to rerun. `-q` limits it to the build, the
default Eva ptests and the Eva native tests. Logs go to the directory it
prints.

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

Fuzzing, WP `qualif` and GUI checks are separate workflows: see
[tests/fuzzing/README.md](tests/fuzzing/README.md),
[plugins/wp/tests/README.md](plugins/wp/tests/README.md) and the Ivette links
above. If the configuration reports Eva or syntax tests as disabled, see
"Limits of this platform" in [docs/agents/setup.md](docs/agents/setup.md).

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
  correct. For a new test, run
  `dune exec -- frama-c-ptests -create-missing-oracles plugins/eva/tests`
  (the argument is a test root, the directory that holds `ptests_config`).
  This writes an empty oracle for every missing one under that root, about
  10,000 files for Eva. Run the test, inspect it, promote its reviewed
  results with `dune promote path/to/the/reviewed.oracle`, then run
  `dune exec -- frama-c-ptests -remove-empty-oracles plugins/eva/tests`
  to delete the empty files. `git status` then lists the new oracles only.
  Bare `dune promote` can accept unrelated pending differences.

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
