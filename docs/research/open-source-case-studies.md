# Open-source case studies as a benchmark suite

Research note for issue #7, "What the open-source case studies offer as a benchmark".

## Sources and conventions

- **OSCS**: `https://git.frama-c.com/pub/open-source-case-studies`, branch `master`, commit `168321b6306abdacee95b22c9c94996f1174ab2c` (committed 2026-10-05), read from a shallow clone. Paths prefixed `OSCS:` are relative to that repository at that commit.
- **This repository**: Frama-C 35~dev (`VERSION`). Paths without a prefix are relative to its root.
- **Public CI**: pipeline 117849 of OSCS, run on commit `168321b6`, `https://git.frama-c.com/pub/open-source-case-studies/-/pipelines/117849`. Job durations come from the GitLab API endpoint `https://git.frama-c.com/api/v4/projects/pub%2Fopen-source-case-studies/pipelines/117849/jobs`; job logs from `https://git.frama-c.com/pub/open-source-case-studies/-/jobs/<id>/raw`.
- Nothing was built or run. No OSCS analysis and no OSCS script was executed.
- Each claim is tagged **[R]** (read in the cited file, log or API response) or **[I]** (inferred from what was read; not observed directly).

The GitHub mirror `https://github.com/Frama-C/open-source-case-studies` is archived. Its last commit is dated 2020-10-29 with the message "Repository moved to Frama-C's Gitlab" [R, GitHub API]. Use the GitLab repository only.

## 1. The programs

`OSCS:summary.md` is a generated table (by `OSCS:compute-summary.sh`) with one row per directory: description, URL, number of Eva targets, number of rows in the alarm files, number of `.c`/`.h` files, lines of code counted by the bundled `OSCS:cloc-2.00.pl`, tags and kind [R]. Licences are listed in `OSCS:README.md`, section "License" [R]. The table below merges both. "Version marker" is what the vendored sources say about their own version; "-" means none was found by a quick search.

| Directory | Origin (URL in `summary.md`) | Files | LoC | Eva targets | Licence | Version marker |
| --- | --- | ---: | ---: | ---: | --- | --- |
| 2048 | github.com/mevdschee/2048.c | 1 | 367 | 1 | MIT | - |
| basic-cwe-examples | cwe.mitre.org/data | 10 | 309 | 17 | MITRE CWE terms of use (`LICENSE`) | - |
| bench-moerman2018 | github.com/JMoerman/JM2018TS | 433 | 18532 | 400 | MIT | - |
| c-testsuite | github.com/c-testsuite/c-testsuite | 220 | 4959 | 215 | MIT for the harness, per-test licences in tag files (`LICENSE`, `LICENSE-tests`) | - |
| c-thread-pool | github.com/Pithikos/C-Thread-Pool | 11 | 588 | 7 | MIT | - |
| c-utils | github.com/barrust/c-utils | 43 | 6392 | 13 | MIT | `CHANGELOG.md` starts at "Future Release" |
| cerberus | cl.cam.ac.uk/~pes20/cerberus | 191 | 2520 | 192 | ISC for most tests, others taken from the literature (`LICENCE`) | `defacto_tarball.tar` (`README-oscs`) |
| chrony | chrony.tuxfamily.org | 122 | 25461 | 2 | GPL | `NEWS` starts at 3.4; `config.h` says "DEVELOPMENT" |
| debie1 | tidorum.fi/debie1 | 48 | 6269 | 1 | specific terms of use (`README.txt`, `terms_of_use-2014-05.pdf`) | benchmark version "e" |
| genann | github.com/codeplea/genann | 8 | 690 | 1 | Zlib | - |
| gnugo | ftp.gnu.org/gnu/gnugo | 27 | 2048 | 1 | GPL | 1.2 (`README`) |
| grayskull | github.com/zserge/grayskull | 5 | 2133 | 2 | MIT | - |
| gzip124 | gnu.org/software/gzip | 35 | 5826 | 1 | GPL | 1.2.4, 18 Aug 93 (`revision.h`) |
| hiredis | github.com/redis/hiredis | 45 | 6622 | 2 | BSD-style (`COPYING`) | 0.15.0 (`hiredis.h`) |
| icpc | icpc2011.cs.usask.ca | 15 | 965 | 1 | Unlicense | - |
| ioccc | github.com/ioccc-src/winner | 55 | 3909 | 21 | CC BY-SA 3.0 | entries of 2019 and 2020 |
| itc-benchmarks | github.com/regehr/itc-benchmarks | 107 | 29633 | 2 | BSD 2-clause | - |
| jsmn | github.com/zserge/jsmn | 7 | 806 | 2 | MIT | - |
| kgflags | github.com/kgabis/kgflags | 5 | 1222 | 2 | MIT | - |
| khash | github.com/attractivechaos/klib | 2 | 308 | 1 | MIT | - |
| kilo | github.com/antirez/kilo | 2 | 1012 | 1 | BSD 2-clause | - |
| libmodbus | github.com/stephane/libmodbus | 22 | 5172 | 2 | LGPL | 3.1.4 (`configure.ac`) |
| libspng | github.com/randy408/libspng | 5 | 3337 | 1 | BSD 2-clause | 0.5.1 (`spng.h`) |
| libyaml | github.com/yaml/libyaml | 25 | 10548 | 2 | MIT | 0.2.5 (`CMakeLists.txt`) |
| line-follower-robot | github.com/Fabio-Morais/Line-Follower-Robot | 21 | 3560 | 1 | MIT, modified BSD for avr-libc | - |
| matrixmult | github.com/mohamedhassan279/Matrix-Multiplication | 1 | 257 | 1 | GPL | - |
| mbedtls | github.com/Mbed-TLS/mbedtls | 423 | 138478 | 179 | Apache-2.0 (`LICENSE`); missing from the README list | 3.4.0 (`include/mbedtls/build_info.h`) |
| microstrain | github.com/ros-drivers/microstrain_mips | 69 | 19075 | 1 | GPL and others (`LICENSE`) | 0.0.3 (`package.xml`) |
| mini-gmp | gmplib.org | 35 | 8686 | 1 | LGPL or GPL | - |
| miniz | github.com/richgel999/miniz | 26 | 8299 | 6 | MIT | 2.1.0 (`ChangeLog.md`) |
| monocypher | monocypher.org | 42 | 23680 | 1 | BSD 2-clause or CC0 (`LICENCE.md`) | 2.0.5 (`VERSION.md`) |
| papabench | github.com/t-crest/patmos-benchmarks, PapaBench-0.4 | 80 | 7251 | 1 | GPL | 0.4 (from the URL) |
| polarssl | github.com/ARMmbed/mbedtls | 118 | 28873 | 1 | GPL | 1.1.7 (`include/polarssl/version.h`) |
| powerwindow | github.com/tacle/tacle-bench | 39 | 2918 | 1 | GPL | - |
| qlz | quicklz.com | 7 | 963 | 4 | GPL | 1.5.0 (`quicklz.h`) |
| safestringlib | github.com/intel/safestringlib | 148 | 14922 | 1 | MIT | - |
| semver | github.com/h2non/semver.c | 4 | 1034 | 1 | MIT | 1.0.0 (`package.json`) |
| snprintf | github.com/mirtoto/snprintf | 4 | 1068 | 66 | GPL | - |
| solitaire | ciphergoth.org/crypto/solitaire | 1 | 263 | 1 | public domain | - |
| stmr | github.com/wooorm/stmr.c | 3 | 497 | 1 | MIT | 1.0.0 (`package.json`) |
| tsvc | polaris.cs.uiuc.edu, `TSVC.tar.gz` | 2 | 4041 | 1 | MIT | - |
| tweetnacl-usable | twitter.com/TweetNaCl | 5 | 1072 | 1 | public domain | - |
| verisec | Verisec paper (ASE 2007) | 320 | 14561 | 275 | several, per application | - |
| x509-parser | github.com/ANSSI-FR/x509-parser | 3 | 5057 | 1 | GPLv2 or BSD | - |

All table cells are [R], from `OSCS:summary.md`, `OSCS:README.md` and the named files inside each directory.

Totals [R, computed from `OSCS:summary.md`]: 44 directories, 1435 Eva targets, 424183 LoC. Without `mbedtls`: 43 directories, 1256 targets, 285705 LoC.

Remarks:

- `mbedtls` is not in the `TARGETS` list of `OSCS:Makefile` and has no job in `OSCS:.gitlab-ci.yml`; `OSCS:compute-summary.sh` hard-codes its alarm count to -1 [R]. It has no tracked oracle [R]. The other 43 directories are the ones the root makefile and the CI run.
- `OSCS:tutorials/` holds teaching material and is in neither list [R].
- The README licence list names a `mibench` directory that does not exist at this commit [R].
- `debie1` is distributed under specific terms of use, not a standard open-source licence. The PDF with the terms was not read.
- Six directories consist of many small targets (bench-moerman2018, c-testsuite, cerberus, verisec, basic-cwe-examples, snprintf); together they hold 1165 of the 1256 targets [R, computed].
- The code is modified relative to upstream: stubs in `.frama-c/`, `#ifdef __FRAMAC__` guards, removed files, and some recursion removed or commented out (`OSCS:README.md`, "Source code modifications"; the `REM_RECURSION` tag; `OSCS:kilo/Eva_patches.md` marks one such patch "[unsound]") [R].
- The README states the purpose: non-regression tests, benchmarking and practical examples, and that "some of the code bases are voluntarily parametrized with suboptimal parameters" [R].

## 2. How an analysis is defined and launched

### Makefiles in OSCS

- Each case study has `OSCS:<dir>/.frama-c/GNUmakefile`. It includes `path.mk` (a symbolic link to `OSCS:path.mk`), then `$(shell $(FRAMAC) -print-lib-path)/analysis-scripts/prologue.mk`, sets `MACHDEP`, `CPPFLAGS`, `FCFLAGS`, `EVAFLAGS`, `TARGETS`, gives one `<t>.parse: <sources>` rule per target, and includes `.../analysis-scripts/epilogue.mk` and `OSCS:Makefile.common` (SARIF export) [R, e.g. `OSCS:2048/.frama-c/GNUmakefile`].
- `OSCS:path.mk` selects the Frama-C binary. If `FRAMAC_DIR` (default `../../frama-c/build/bin`) exists, it sets `FRAMAC`, `FRAMAC_GUI` and exports `OCAMLPATH=$(FRAMAC_DIR)/../lib:$(OCAMLPATH)`. Otherwise it requires `frama-c` in `PATH` [R].
- `OSCS:Makefile` (root) offers `submodules`, `framac`, `all`, `quick`, `clean`, `parse`, `sarif`, `summary`, `display-targets`, `<dir>` and `<dir>/<t>.eva`. `<dir>` runs `make -C <dir>/.frama-c` [R].
- `OSCS:.gitmodules` declares one submodule, `frama-c`, from `https://git.frama-c.com/pub/frama-c.git`. The gitlink at this commit is `6221dd5f44d302a86d9ade2df56bce5b29511d7c` [R]. `make framac` builds it and installs it under `frama-c/build` [R].
- `OSCS:.gitlab-ci.yml` uses the Docker image `framac/frama-c:dev`. Each job runs `make -C $TARGET/.frama-c clean`, `make $TARGET`, `git diff --exit-code $TARGET`, `make $TARGET.sarif`, then deletes the `.sav` files [R]. The CI log says "Skipping Git submodules setup", so CI uses the image's `frama-c` from `PATH`, not the submodule [R, job 2116731].

### Scripts from the Frama-C tree

OSCS finds these through `frama-c -print-lib-path`; they are installed from `share/analysis-scripts/` (`share/dune`, lines 40-57) [R].

- `share/analysis-scripts/prologue.mk` includes `analysis.mk` and sets the default goal [R].
- `share/analysis-scripts/analysis.mk` holds the rules `%.parse`, `%.eva`, `%.wp`, `%.gui` [R].
- `share/analysis-scripts/epilogue.mk` defines `eva`, `parse`, `gui`, `all`, `display-targets` from `TARGETS` [R].
- `share/analysis-scripts/cmd-dep.sh` writes the command line to `<target>/command` only when it changed, so that a change of flags triggers a rerun [R].
- `share/analysis-scripts/parse-coverage.sh` extracts coverage counts from `eva.log` into `stats.txt` [R].
- `share/analysis-scripts/summary.py`, with `frama_c_results.py`, `results_display.py`, `benchmark_database.py`, `git_utils.py` and `clone.sh`, is the benchmarking front end (`frama-c-script summary`, `bin/frama-c-script` line 248; OSCS `make summary`) [R].
- `bin/frama-c-script` also provides `flamegraph` (uses `share/analysis-scripts/flamegraph.pl`), `configure` and `make-machdep`, which some case studies use [R].
- `OSCS:bench_ast_diff.py` imports `frama_c_results` from the installed `analysis-scripts` directory [R].
- Nothing under `tools/` (`hdrck`, `lint`, `ptests`) is referenced by OSCS [R, grep].
- The user manual chapter is `doc/userman/user-analysis-scripts.tex`; its section "Practical Examples: Open Source Case Studies" says OSCS is "periodically synchronized w.r.t. the public Frama-C repository (daily snapshots)" [R].

### The commands that run

Parsing (`share/analysis-scripts/analysis.mk`, lines 163-202) [R]:

```
frama-c $(PARSEFLAGS) $(FCFLAGS) -machdep $(MACHDEP) -cpp-extra-args="$(CPPFLAGS)" <sources>
  -kernel-log w:<t>.parse/warnings.log -metrics -metrics-log a:<t>.parse/metrics.log
  -save <t>.parse/framac.sav -print -ocode <t>.parse/framac.ast -then -no-print
```

Eva (`share/analysis-scripts/analysis.mk`, lines 211-252) [R]:

```
frama-c $(FCFLAGS) -eva $(EVAFLAGS) -load <t>.parse/framac.sav
  -eva-flamegraph <t>.eva/flamegraph.txt
  -kernel-log, -from-log, -inout-log, -scope-log, -eva-log  w:<t>.eva/warnings.log
  -eva-statistics-file <t>.eva/eva-stats.csv -save <t>.eva/framac.sav
  -then -report-csv <t>.eva/alarms.csv -report-no-proven -report-log w:<t>.eva/warnings.log
  -metrics-eva-cover -metrics-log a:<t>.eva/metrics.log -nonterm -nonterm-log a:<t>.eva/nonterm.log
```

Default `EVAFLAGS` (`share/analysis-scripts/analysis.mk`, lines 120-127) [R]:

```
-eva-no-show-progress -eva-msg-key=-initial-state,-final-states,callstacks
-eva-warn-key alarm=inactive -eva-warn-key garbled-mix=warning,garbled-mix:write=warning
-calldeps -from-verbose 0 -cache-size 8
```

Consequences:

- Each case study appends to these defaults with `EVAFLAGS +=`, because `prologue.mk` is included first [R for the makefiles, I for the resulting command].
- `-calldeps` makes the From plug-in compute callwise dependencies during the Eva run. That code keeps its own table keyed by Eva's memexec counter (`plugins/from/src/callwise.ml`, lines 87-135) [R].
- `-cache-size 8` raises the kernel cache size from its default of 2 (`src/kernel/services/plugin_entry_points/kernel.ml`, lines 1945-1958) [R].
- Every target saves the full session twice: `<t>.parse/framac.sav` and `<t>.eva/framac.sav` [R].
- Setting `BENCHMARK=<tag>` forces the `.eva` rule to rerun and writes the tag into `stats.txt` (`analysis.mk`, lines 213 and 246) [R].
- Setting `AST_DIFF` makes the parse rule reload the previous `framac.sav` and apply `-ast-diff`, and makes the Eva rule add `-eva-load <t>.eva/framac.sav` (`analysis.mk`, lines 53-57, 176-183, 204-209) [R]. The string `-eva-load` occurs nowhere else in this repository except as part of `-eva-load-fun-state` in `dev/frama-smith-templates.json`; no Eva parameter with that name is defined in `plugins/eva/src/parameters.ml` [R, grep]. So `OSCS:bench_ast_diff.py`, which sets `AST_DIFF=1` and compares `user_time` with and without it, probably cannot complete its second pass with this tree [I].

### Is `-eva-memexec` left on?

Yes.

- `-eva-memexec` defaults to true (`plugins/eva/src/parameters.ml`, lines 1017-1025) [R].
- The string "memexec" does not occur anywhere in OSCS at this commit (case-insensitive `git grep`) [R].
- Nothing in `share/analysis-scripts/` or `bin/` mentions it [R, grep]. The only hit under `share/` is a stale completion entry in `share/_frama-c.zsh`.
- The parameter is read in one place, `plugins/eva/src/engine/compute_functions.ml` line 197, and no code sets it [R, grep].
- For the two `-mthread` case studies (c-thread-pool, matrixmult), the cache is cleared before each thread analysis (`plugins/eva/src/engine/analysis.ml`, line 195) [R].

So the option is on in every OSCS Eva run, and the hit and miss counts per function are written to `eva-stats.csv` (section 3) [I].

How much the cache is used also depends on the abstract domains. A domain whose `relate` function returns top disables the cache (`plugins/eva/src/domains/abstract_domain.ml`, lines 332-345) [R]. `-eva-precision n` enables symbolic-locations from 1, equality from 2, gauges from 3 and octagon from 5, and sets `-eva-octagon-through-calls` from 7 (`plugins/eva/src/parameters.ml`, lines 1404-1433) [R], so most case studies run with relational domains. For the four domains OSCS enables, `relate` does not return top in the configuration read: symbolic-locations returns empty (`plugins/eva/src/domains/symbolic_locs.ml`, line 576); gauges returns empty with its compiled-in `IntraproceduralNonReferenced` mode (`plugins/eva/src/domains/gauges/gauges_domain.ml`, lines 30 and 1257-1260); octagon returns empty unless `-eva-octagon-through-calls` is set, and related bases otherwise (`plugins/eva/src/domains/octagons.ml`, lines 1851-1864); equality returns the related bases (`plugins/eva/src/domains/equality/equality_domain.ml`, lines 534-545) [R]. The effect of these domains on the hit rate was not measured.

### Per-program Eva options

All from `OSCS:<dir>/.frama-c/GNUmakefile` [R]. Flags that only turn a warning into an abort (`-eva-warn-key builtins:missing-spec=abort` and similar) are omitted.

| Directory | Eva options added to the defaults |
| --- | --- |
| 2048, kgflags, libyaml, mini-gmp, miniz, ioccc, solitaire | none that affect precision |
| basic-cwe-examples | none; the `-precise` variants add `-eva-precision` 1, 2 or 5 on three targets |
| bench-moerman2018 | `-eva-precision 3` |
| c-testsuite | `-eva-precision 3 -eva-unroll-recursive-calls 10` |
| c-thread-pool | `-mthread -eva-precision 5 -eva-verbose 3` |
| c-utils | per target: `-eva-precision` 5 or 8, `-eva-no-alloc-returns-null`, some with `-eva-alloc-builtin fresh`, `-eva-unroll-recursive-calls 15`, `-eva-plevel 1000000` |
| cerberus | `-eva-slevel 6000`, restricted plug-in list |
| chrony | `-eva-mlevel 1 -eva-domains equality,gauges`, `-eva-domains-function symbolic-locations:<f>` for six functions, `-eva-use-spec`, `-eva-malloc-functions`; `chrony-regress` adds `-eva-domains octagon` |
| debie1 | `-eva-domains equality -eva-auto-loop-unroll 180` |
| genann | `-eva-slevel 9` |
| gnugo | `-eva-slevel 5 -eva-domains symbolic-locations` |
| grayskull | `-eva-precision` 1 and 7 on its two targets |
| gzip124 | `-eva-slevel 2 -eva-no-alloc-returns-null` |
| hiredis | `-eva-ilevel 16` |
| icpc | `-eva-slevel 16 -eva-domains equality` |
| itc-benchmarks | `-eva-precision 3 -eva-mlevel 10 -eva-no-alloc-returns-null -eva-builtin titcb_pow:Frama_C_pow` |
| jsmn | `-eva-slevel 300 -eva-no-alloc-returns-null` |
| khash, qlz, line-follower-robot | `-eva-no-alloc-returns-null` |
| kilo | `-eva-slevel 2 -eva-no-alloc-returns-null` |
| libmodbus | `-eva-precision 4 -eva-split-return full -eva-no-alloc-returns-null` |
| libspng | `-eva-precision 5 -eva-plevel 256` |
| matrixmult | `-mthread -eva-precision 4 -eva-verbose 3` |
| mbedtls | `-eva-precision 2 -eva-unroll-recursive-calls 2` |
| microstrain | `-eva-precision 2` |
| monocypher | `-eva-slevel 8 -eva-split-return auto -eva-warn-key signed-overflow=inactive` |
| papabench | `-eva-precision 1` |
| polarssl | `-eva-slevel 2 -eva-ilevel 13 -eva-subdivide-non-linear 16 -eva-no-alloc-returns-null`, `-eva-use-spec` for 43 functions |
| powerwindow | `-eva-auto-loop-unroll 368` |
| safestringlib | `-eva-precision 3` |
| semver | `-eva-slevel 82 -eva-alloc-builtin fresh` |
| snprintf | `-eva-precision 5` |
| stmr | `-eva-precision 2` |
| tsvc | `-eva-precision 1` |
| tweetnacl-usable | `-eva-auto-loop-unroll 64 -eva-no-alloc-returns-null -no-warn-signed-overflow` |
| verisec | `-eva-precision 6`, restricted plug-in list |
| x509-parser | `-eva-precision 2 -eva-warn-undefined-pointer-comparison none`, plus kernel `-warn-*` overflow and downcast options |

Whether every option used by these makefiles still exists in this tree was not checked.

## 3. What a run records

Files written in `<dir>/.frama-c/<t>.parse/` and `<dir>/.frama-c/<t>.eva/` (`share/analysis-scripts/analysis.mk`) [R]:

| File | Content | Tracked in OSCS |
| --- | --- | --- |
| `<t>.parse/framac.ast` | pretty-printed normalised code (`-print -ocode`) | yes |
| `<t>.parse/metrics.log`, `<t>.parse/warnings.log` | syntactic metrics; kernel warnings | yes |
| `<t>.eva/alarms.csv` | `-report-csv -report-no-proven`: one tab-separated row per property that is not proven, with directory, file, line, function, property kind, status, property | yes |
| `<t>.eva/metrics.log` | `-metrics-eva-cover`: function and statement coverage, per function | yes |
| `<t>.eva/warnings.log` | warnings of kernel, From, Inout, Scope, Eva, Report | yes |
| `<t>.eva/nonterm.log` | output of the Nonterm plug-in | yes |
| `<t>.parse/stats.txt`, `<t>.eva/stats.txt` | `key=value` lines, see below | no |
| `<t>.eva/eva-stats.csv` | Eva internal statistics, see below | no |
| `<t>.eva/flamegraph.txt` | time per call stack, for `flamegraph.pl` | no |
| `<t>.parse/parse.log`, `<t>.eva/eva.log` | full console output | no |
| `<t>.parse/framac.sav`, `<t>.eva/framac.sav` | saved sessions | no |
| `<t>.sarif` | SARIF report (`OSCS:Makefile.common`) | no |
| `command`, `running` | command line of the last run; marker while running | no |

The "Tracked" column follows `OSCS:.gitignore` and `git ls-files`: 1256 target directories each have the seven tracked files [R]. The tracked files total about 35 MB, of which `framac.ast` is 28.8 MB [R, computed].

`stats.txt` of an Eva run holds [R, `analysis.mk` lines 218, 240-247 and `parse-coverage.sh`]:

- `user_time` and `memory`: from GNU `time -f 'user_time=%U\nmemory=%M'`, that is user CPU seconds and maximum resident set size in KiB of the whole `frama-c` process.
- `sem_reach_fun`, `syn_reach_fun`, `total_fun`, `sem_reach_stmt`, `syn_reach_stmt`: coverage counts parsed from `eva.log`.
- `timestamp`, `warnings` (count of "Warning:" in `warnings.log`), `alarms` (lines of `alarms.csv` minus one), `cmd_args`, `benchmark_tag`.

Points that matter for a benchmark:

- `user_time` covers the whole process: loading the parse session, Eva, From with `-calldeps`, saving, the report, coverage metrics and Nonterm [I from the command line]. It is not Eva time alone.
- `time` is used only if `env time -f ... -o ...` works. The `gtime` fallback is defined and then overwritten by an empty definition (`analysis.mk`, lines 78-84), so without GNU `time` under the name `time`, `stats.txt` has no `user_time` or `memory` [R for the text, I for the effect].
- `eva-stats.csv` holds Eva's own statistics, one tab-separated row per name, function, statement and value (`plugins/eva/src/utils/statistics.ml`, lines 273-287) [R]. Registered statistics (same file, lines 305-330): `analysis-time`, `memory-usage`, `alarm-count`, `stmt-coverage`, `fun-coverage`, `memexec-hits` and `memexec-misses` per function, `iterations`, `max-widenings` and `max-unrolling` per statement, `partitioning-index-hits`, `partitioning-index-misses` [R]. This is the file that gives Eva-only time and memexec effectiveness.
- "Alarms" in `summary.md` and `stats.txt` means rows of `alarms.csv`, which is not Eva's alarm count. For 2048 the file has 17 rows while the CI log of the same target prints "7 alarms generated by the analysis"; the rows also include unproven preconditions, once at the call site and once at the libc declaration [R, `OSCS:2048/.frama-c/2048.eva/alarms.csv` and job 2116731].
- Over all tracked `alarms.csv`, 15493 rows have status "Unknown" and 699 "Invalid or unreachable" [R, computed].
- Rows for libc properties carry the line number inside the Frama-C libc header (`FRAMAC_SHARE/libc stdio.h 238 ...`), so the file changes when the libc headers change [R].

Aggregation tools [R unless noted]:

- `OSCS:show_stats.sh` prints user time and memory from `stats.txt` for given targets or for all.
- `share/analysis-scripts/summary.py` polls `stats.txt` of all targets while `make all` runs. With `-b` it runs sequentially with a fresh `BENCHMARK` tag and appends to `benchmark-results.db` (SQLite) and `benchmark-results.csv`: analyzer revision and hash, target, target hash, user time, memory, alarms, warnings, coverage counts, command line (`benchmark_database.py`, lines 78-164). It can compare with a reference revision (`--vs`).
- `summary.py` line 58 calls `target.endswith(".eva", ".parse")`. In Python the second positional argument of `str.endswith` is a start index, so this expression raises `TypeError` [R for the line; the expression was evaluated in isolation with Python 3.12, the script was not run]. `clone.sh` line 14 defaults to an SSH address on git.frama-c.com (project `frama-c/frama-c`, not the public `pub/frama-c`) when asked to fetch a revision [R]. Treat `frama-c-script summary` as untested for this purpose.
- `OSCS:bench-moerman2018/.frama-c/evaluate_case.sh` and the tracked `eval_summary.txt` classify each of the 400 targets as ok, imprecise or unsound from the row count of `alarms.csv` [R].

## 4. Published or recorded times and result sizes

- OSCS records no analysis time, no memory figure and no result size. `stats.txt`, `eva-stats.csv`, `flamegraph.txt` and `*.sav` are ignored by `OSCS:.gitignore`, and no such file is tracked [R].
- The only ordering information in the repository is `SLOW_TARGETS=monocypher chrony debie1 polarssl libmodbus`, commented "Targets sorted by longest-running first" (`OSCS:Makefile`) [R].
- Comments in makefiles [R]: `OSCS:x509-parser/.frama-c/GNUmakefile` "-eva-precision 5 does not terminate in 30 minutes"; `OSCS:monocypher/.frama-c/GNUmakefile` "-eva-domains gauges : -6 alarms, +1m30 analysis time"; `OSCS:c-testsuite/.frama-c/GNUmakefile` "00041.c : full loop unrolling requires > 3 minutes".
- Saved sessions are never published: CI deletes `*.sav` before collecting artifacts, which expire after 5 days (`OSCS:.gitlab-ci.yml`) [R]. No size of a `framac.sav` was found anywhere.

Public CI gives whole-job durations. For pipeline 117849 (2026-10-05, image `framac/frama-c:dev`), in seconds [R, GitLab API]:

| Job | s | Job | s | Job | s | Job | s |
| --- | ---: | --- | ---: | --- | ---: | --- | ---: |
| monocypher | 514 | libmodbus | 183 | kilo | 76 | kgflags | 37 |
| chrony | 377 | safestringlib | 171 | tsvc | 76 | basic-cwe-examples | 36 |
| bench-moerman2018 | 365 | matrixmult | 168 | microstrain | 67 | genann | 36 |
| verisec | 288 | cerberus | 162 | semver | 64 | c-thread-pool | 32 |
| polarssl | 281 | grayskull | 154 | libyaml | 61 | stmr | 31 |
| debie1 | 279 | ioccc | 131 | papabench | 47 | powerwindow | 29 |
| miniz | 236 | c-utils | 122 | jsmn | 42 | tweetnacl-usable | 24 |
| gzip124 | 225 | hiredis | 105 | icpc | 42 | 2048 | 23 |
| c-testsuite | 198 | x509-parser | 85 | khash | 39 | qlz | 19 |
| libspng | 196 | itc-benchmarks | 81 | line-follower-robot | 37 | solitaire | 16 |
| snprintf | 185 | gnugo | 77 | mini-gmp | 37 | | |

The sum is 5453 s. These are wall-clock durations of a whole job: container start, checkout, clean, parse and Eva for every target of the directory, the oracle diff and, when that passes, the SARIF export. They come from one run on a shared runner whose load is unknown [I].

Phase times read from log timestamps of three jobs [R; wall clock]:

| Target | Parse | Eva until the analysis summary | Rest of the Eva command (report, metrics, Nonterm, save) |
| --- | ---: | ---: | ---: |
| 2048 (job 2116731) | 0.8 s | about 1.1 s | under 0.3 s |
| debie1 (job 2116739) | 2.3 s | 4 min 1 s | 3 s |
| monocypher (job 2116760) | 15.7 s | 7 min 39 s | 8.5 s |

Job duration against number of targets, for the jobs above 150 s [R, both tables]:

- one target: monocypher 514 s, polarssl 281 s, debie1 279 s, gzip124 225 s, libspng 196 s, safestringlib 171 s, matrixmult 168 s;
- two targets: chrony 377 s, libmodbus 183 s, grayskull 154 s;
- six targets: miniz 236 s;
- many targets: bench-moerman2018 365 s (400), verisec 288 s (275), c-testsuite 198 s (215), snprintf 185 s (66), cerberus 162 s (192).

No job, hence no single analysis, exceeded 9 minutes in this run [R]. The six directories with many small targets (section 1) sum to 1234 s for 1165 targets, about 1.1 s per target with job overhead included [R, computed].

## 5. Upstream histories and how sources are pinned

How OSCS pins a source version:

- Sources are vendored copies inside the OSCS repository. `OSCS:CONTRIBUTING.md` step 1 says to copy a release archive or a clone with `.git` removed, and "we currently do not use submodules for case studies" [R]. The only submodule is `frama-c` [R].
- `OSCS:<dir>/OSCS-README.txt` has four lines: description, URL, tags, kind. It records no upstream version, tag or commit [R].
- The upstream version is therefore known only from version markers inside the vendored sources (table in section 1) or from the OSCS commit that imported the directory [I]. The OSCS history was not read (shallow clone).
- Two case studies record the configuration used to produce the committed `config.h`: `OSCS:chrony/configure-used-for-oscs.txt` and `OSCS:libmodbus/configure-for-oscs.txt` [R].
- A cross-version pair cannot reuse the OSCS copy unchanged for the other version: the stubs, `#ifdef __FRAMAC__` edits and file lists in the `GNUmakefile` are specific to the imported snapshot [I].

Upstream projects with a public Git history. "Tags" is the number of tags returned by `git ls-remote --tags` on the GitHub repository on 2026-11-17 [R]; "match" says whether a tag equal to the vendored version marker exists.

| Case study | Upstream repository | Tags | Vendored marker and match |
| --- | --- | ---: | --- |
| mbedtls | github.com/Mbed-TLS/mbedtls | 292 | 3.4.0: tags `v3.4.0` and `mbedtls-3.4.0` exist |
| polarssl | same repository | 292 | 1.1.7: tag `polarssl-1.1.7` exists |
| libmodbus | github.com/stephane/libmodbus | 36 | 3.1.4: tag `v3.1.4` exists |
| monocypher | github.com/LoupVaillant/Monocypher | 42 | 2.0.5: tag `2.0.5` exists |
| libyaml | github.com/yaml/libyaml | 21 | 0.2.5: tag `0.2.5` exists |
| miniz | github.com/richgel999/miniz | 22 | 2.1.0: tag `2.1.0` exists |
| hiredis | github.com/redis/hiredis | 29 | 0.15.0: no tag named `v0.15.0` |
| libspng | github.com/randy408/libspng | 23 | 0.5.1: no tag named `v0.5.1` |
| semver | github.com/h2non/semver.c | 7 | 1.0.0: tag `v1.0.0` exists |
| stmr | github.com/wooorm/stmr.c | 6 | 1.0.0: tag `1.0.0` exists |
| snprintf | github.com/mirtoto/snprintf | 8 | no marker |
| c-utils | github.com/barrust/c-utils | 7 | "Future Release", so between tags |
| 2048 | github.com/mevdschee/2048.c | 6 | no marker |
| safestringlib | github.com/intel/safestringlib | 4 | no marker |
| genann | github.com/codeplea/genann | 3 | no marker |
| jsmn | github.com/zserge/jsmn | 2 | no marker |
| kilo, x509-parser, kgflags, grayskull, c-thread-pool | GitHub repositories named in section 1 | 0 | history without tags |

Not queried, but the URL in `summary.md` is a GitHub repository, so a commit history exists [I]: bench-moerman2018, c-testsuite, ioccc, itc-benchmarks, khash (klib), line-follower-robot, matrixmult, microstrain, papabench (patmos-benchmarks), powerwindow (tacle-bench).

`summary.md` gives a web page, an archive or a paper, not a repository, for: basic-cwe-examples, cerberus, chrony, debie1, gnugo, gzip124, icpc, mini-gmp, monocypher, qlz, solitaire, tsvc, tweetnacl-usable, verisec [R]. Whether chrony, gzip, GMP or gnugo publish a version-control history elsewhere was not checked; monocypher does (table above).

Candidates for cross-version pairs, by this evidence [I]:

- vendored version matched to an upstream tag, more than 20 tags: mbedtls and polarssl (same lineage, but mbedtls is outside the CI set and needs clang), libmodbus, monocypher, libyaml, miniz;
- many upstream tags but the vendored version was not matched (only one tag-name pattern was tried): hiredis, libspng.

## 6. Running one case study with a Frama-C built from this repository

Nothing below was run; the steps are derived from the files cited [I unless tagged].

1. Build and install Frama-C to a prefix. `Makefile` line 42 (`all`) runs `dune build @install`; `install` (`Makefile` line 92, `share/Makefile.installation` lines 58-78) runs `dune install --prefix "$PREFIX"` and requires `PREFIX` [R]. OSCS does the same on its submodule: `make -C frama-c clean`, `make -C frama-c -j`, `make -C frama-c install PREFIX=<oscs>/frama-c/build` (`OSCS:Makefile`, target `frama-c/build/bin/frama-c`) [R]. An installed tree is needed because the makefiles call `frama-c -print-lib-path` and expect `analysis-scripts/` under it; the installed scripts are then those of this repository, not of the OSCS submodule.
2. Point OSCS at that installation, using one of the modes of `OSCS:path.mk` [R]:
   - leave the `frama-c` submodule uninitialised and put `<prefix>/bin` first in `PATH` (this is what CI does); or
   - set `FRAMAC_DIR` to `<prefix>/bin`, by editing `OSCS:path.mk` or on the `make` command line. `path.mk` then exports `OCAMLPATH=<prefix>/lib:$OCAMLPATH` and sets `FRAMAC`.
   In the `PATH` mode, `OCAMLPATH` is not set by `path.mk`; `share/Makefile.installation` prints a reminder to export `OCAMLPATH="$PREFIX/lib:$OCAMLPATH"` after a prefix install [R].
3. Run the analysis from the OSCS root: `make -C <dir>/.frama-c` for all targets of the directory, or `make -C <dir>/.frama-c <t>.parse` and `<t>.eva` for one target, or `make <dir>` and `make <dir>/<t>.eva` [R].
4. After changing the Frama-C binary, run `make -C <dir>/.frama-c clean` first or pass `-B`: "targets are not marked as dependent on Frama-C itself" (`OSCS:Makefile`, help text) [R].

Make targets: `clean`, `<t>.parse`, `<t>.eva`, `all`, `display-targets`, optional `<t>.sarif` [R]. `make framac` is optional when another Frama-C is used (`OSCS:Makefile`, help text; `OSCS:README.md`, "Troubleshooting / Debugging") [R].

Variables [R, `share/analysis-scripts/analysis.mk` lines 13-57 and 93]: `FRAMAC`, `FRAMAC_DIR`, `OCAMLPATH`; optional `BENCHMARK`, `AST_DIFF`, `FLAMEGRAPH`, `SILENT=yes`; `CPPFLAGS`, `FCFLAGS`, `EVAFLAGS`, `PARSEFLAGS`, `MACHDEP` can be overridden. Passing `EVAFLAGS=...` on the `make` command line replaces both the defaults and the per-program additions, since command-line variables override makefile assignments [I].

External dependencies:

- GNU Make 4.0 or newer (`analysis.mk` line 60 aborts otherwise) and Bash (line 152) [R].
- GNU `time` reachable as `time`, otherwise no time or memory is recorded (section 3).
- `sed`, `tee`, `date`, `grep`, `expr`, `diff` [R].
- Python 3.7 or newer for the optional scripts (`OSCS:README.md`); Perl for `cloc` and `flamegraph.pl` [R].
- Frama-C plug-ins used by the Eva rule: Eva, From, Inout, Scope, Report, Metrics, Nonterm (the list also appears in `OSCS:verisec/.frama-c/GNUmakefile`); Markdown-report for SARIF; Mthread for c-thread-pool and matrixmult; WP, Why3 and Alt-Ergo only for the optional `x509-parser.wp` target; E-ACSL only for the optional `eacsl` target of x509-parser [R].
- `clang` for mbedtls only: its makefile preprocesses with `clang -C -E` and regenerates `machdep_leon4.yaml` with `frama-c-script make-machdep --compiler clang` [R].
- The OCaml and opam dependencies needed to build Frama-C itself are in `INSTALL.md` and `opam`; they were not enumerated here.

## 7. Limits for benchmarking

- **A run overwrites tracked files.** The outputs are written next to the tracked oracles, so any run with a Frama-C that differs from the one used for the oracles leaves the OSCS working tree modified [I]. Copy the tree or reset it between configurations.
- **The oracles at this commit do not match the `framac/frama-c:dev` image cached on the CI runner.** The log shows pull policy `if-not-present` and a locally found image, so the image may be older than the current tag [R, job 2116731]. In pipeline 117849, 34 of 43 jobs failed and 9 passed (debie1, x509-parser, gnugo, icpc, khash, line-follower-robot, powerwindow, tweetnacl-usable, solitaire) [R, API]. In the two failed logs that were read, the analysis completed and the failure was `git diff --exit-code`: shifted libc line numbers in `alarms.csv` and statement counts differing by one in `metrics.log` [R, jobs 2116731 and 2116760]. That the other 32 failures have the same cause is assumed [I]. The five most recent `master` pipelines, back to 2026-09-11, all have status failed [R, API]. Alarm rows and coverage counts are thus tied to an exact Frama-C revision, including its libc.
- **The Frama-C pin differs from this repository.** The submodule points to `6221dd5f` of `https://git.frama-c.com/pub/frama-c.git`; it is not an ancestor of this repository's `HEAD` [R, `git merge-base --is-ancestor` on objects already present locally]. Results obtained with a build of this repository should not be expected to equal the tracked oracles [I]. The GitLab web interface of git.frama-c.com refuses commit and raw-file pages ("accessing to commit details from the GitLab web interface is now denied") [R], so that commit can only be inspected through a clone.
- **Time and memory fields vary between runs.** `stats.txt` (timestamp, user time, peak memory), `eva-stats.csv` (analysis time, memory usage) and `flamegraph.txt` are measurements [R]. The tracked files are meant to be reproducible for a fixed Frama-C, since CI diffs them [I]; nine jobs passed that diff in the run read. No repeated-run data exists to quantify timing variance.
- **Parallelism.** `OSCS:Makefile` lets `make -j` run targets concurrently, and `summary.py` without `-b` adds `-j <cpu count>` [R]; timings from parallel runs are not comparable [I]. `.NOTPARALLEL` is not set anywhere.
- **Staleness is not tracked.** Targets do not depend on the Frama-C binary (`OSCS:Makefile`), and header changes do not trigger a reparse (`doc/userman/user-analysis-scripts.tex`, "Technical Notes") [R].
- **Parsing is a separate step with its own saved session.** On the smallest target read (2048) it takes about as long as Eva (section 4) [R]. A reuse experiment must decide whether it starts from `<t>.parse/framac.sav` or from sources [I].
- **Programs that do not finish quickly.** By the CI run, the analyses that take minutes are the single-target jobs monocypher, polarssl, debie1, gzip124, libspng, safestringlib and matrixmult (168 s to 514 s per job) and the two-target jobs chrony, libmodbus and grayskull (section 4) [R]. Per-target times inside multi-target jobs were not read. Raising precision can prevent termination in practical time: see the x509-parser, monocypher and c-testsuite comments in section 4 [R]. mbedtls (179 targets, 138 kLoC) has no recorded run at all [R].
- **Most targets are tiny.** 1165 of 1256 targets belong to six directories and average about 1.1 s each in the CI run [R, computed]. They measure start-up, loading and saving more than fixpoint computation [I].
- **Suboptimal settings by design.** The README says some case studies are deliberately parametrised with suboptimal parameters, and only a few are "finalized" (it recommends debie1) [R].
- **Generated or environment-dependent inputs.** mbedtls regenerates `machdep_leon4.yaml` with clang; chrony and libmodbus ship a committed `config.h` produced by `configure` with the recorded options; snprintf and hiredis add files from `$(frama-c -print-share-path)/libc/` (`string.c`, `netdb.c`) to their sources, so their input depends on the Frama-C installation [R].
- **Network.** Running a parse or Eva target needs no network: no analysis makefile contains a download command or URL [R, grep]. The network is needed for `make submodules` and `make framac` (clone of Frama-C), for the Docker image `framac/frama-c:dev`, and for `summary.py REVISION`, which clones Frama-C through `clone.sh` [R].
- **`AST_DIFF` mode and `frama-c-script summary`** have the defects described in sections 2 and 3 and should not be relied on without testing.

## Not checked

- No analysis was run. Every statement about what a command does when executed is derived from makefiles, scripts and CI logs.
- Whether all Eva and kernel options used by the 44 `GNUmakefile`s exist in this repository's Frama-C.
- The Frama-C revision inside the `framac/frama-c:dev` image used by CI, and whether the tracked oracles match the submodule pin `6221dd5f`.
- The cause of failure of 32 of the 34 failed CI jobs (only the 2048 and monocypher logs were read; debie1's passing log was read).
- Per-target CPU time, peak memory and the size of any `framac.sav`. None is published in the repository; CI job durations are the only public numbers found.
- Publications outside the repository (Frama-C blog, papers, other manuals under `doc/`) were not searched for OSCS timings.
- The memexec hit rate of any case study, and the effect of the relational domains on it.
- The OSCS commit history (import dates and upstream versions of each directory), because the clone was shallow.
- Upstream histories of the projects not listed in the tag table; the exact upstream commit of any vendored copy; whether the vendored sources equal the tagged upstream release.
- The licence texts in full. Licences are as stated by `OSCS:README.md` plus the first lines of the files named there; the debie1 terms-of-use PDF was not read.
- Whether an uninstalled `dune` build (through `bin/frama-c`, a `dune exec` wrapper) works with the OSCS makefiles.
- Whether `-mthread` analyses or any other target produce run-to-run differences in the tracked files.
- `tutorials/`, the WP and E-ACSL targets of x509-parser, and the SARIF export.
