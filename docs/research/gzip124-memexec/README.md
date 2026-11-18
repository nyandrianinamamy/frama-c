# Why identical gzip124 analyses can have different body counts

Memexec can find two entries for the same call and input. The first match in a hash table wins. For `huft_free` the two entries reconstruct different return states. That changes which later calls hit. An extra miss analyses the body and can execute the `free` builtin twice.

## What ran

Analyzer `90a4b4cc5313ba9ebbdadda7f93cc60630ea6747`, case studies `168321b6306abdacee95b22c9c94996f1174ab2c`, x86_32, cvalue, slevel 2, memexec enabled, allocation returns non-null. All five rows below load the same saved parse in fresh processes using the same trace binary. They are untimed diagnostic runs. The trace enumerates all matching base sets, using the regular domain reconstruction for each. The default selects the first visited match. The two interventions select the lowest or highest saved call number among the candidates returned by the per-base-set state tables. This probe does not change the state table's treatment of duplicates under a single key.

| Selection | OCaml minor heap | Bodies | huft_free hits | huft_free misses | free applications |
|---|---|---:|---:|---:|---:|
| First visited | Default | 6,003 | 1,372 | 179 | 404 |
| First visited | 64k words | 5,999 | 1,376 | 175 | 396 |
| Oldest candidate | Default | 5,991 | 1,384 | 167 | 380 |
| Oldest candidate | 64k words | 5,991 | 1,384 | 167 | 380 |
| Newest candidate | Default | 6,011 | 1,364 | 187 | 420 |

The original allocation-counter campaign and its same-binary repeat already showed the first two count patterns with the original early-exit lookup. Four fresh runs with the earlier heap-counter binary, first-match lookup and a fixed parse gave 5,995 each. Changing the minor heap from 262,144 to 524,288 words in that binary gave 5,995 and 6,003. Probe allocations can shift the observed totals. The range above describes observations only.

## Where the runs diverged

- In the default trace, 241 lookups had multiple matching base sets, all for `huft_free`. At lookup 5,276, entries 615 and 935 both matched. The default chose 935 and the 64k-word run chose 615. At lookup 5,291 the former missed and the latter hit entry 618. Compressed logs give lookup ordinal, function, matching saved call numbers (in reverse visitation order), and chosen entry. A lookup reaching the table but finding no match has choice −1. The trace omits early misses before the base-set table is found.
- In the detailed probe, the key of 615 includes `bb` and `bk`. Its replay writes their saved values back. Entry 935 leaves them in the calling state. Direct equality of the two reconstructed partitioned outputs returned false. In the state returned by 615 both values include `ESCAPINGADDR`. The state returned by 935 omits it. The exact keys and value differences are in [matching-keys.txt](matching-keys.txt) and [call-output.diff](call-output.diff).
- Source at the analyzer revision: `plugins/eva/src/engine/mem_exec.ml` stores by actual arguments, input-base set and projected state. In `find_match_in_previous`, `Base.Hptset.Hashtbl.iter` visits candidate sets and the first successful state lookup raises `Result_found`. In `plugins/eva/src/domains/cvalue/cvalue_domain.ml`, `reuse` overlays the stored output on the current input. `free` computes its writes by scanning for pointers to the freed bases (`builtins_malloc.ml`, `free`). Different histories can therefore give different input and output base sets.
- The base-set hash is a hash-consed tree's allocation tag (`src/lib/utils/hptset.ml`, `Make`; `src/lib/utils/hptmap.ml`, `hash_generic`, `wrap_Leaf`, `wrap_Branch`). The default hash-consing table uses weak references (`src/lib/project/state_builder.ml`, `Hashconsing_tbl`). GC can reclaim an unreferenced node, and constructing it again can consume another tag. The detail probe measured the same base set for entry 935 hashing to 5,132 versus 5,130 under different minor heap sizes, with 615 hashing to 3,792 in both. The trace probe directly observed the reversal of iteration order. No individual collection or reclaimed node was traced.

## What changed in the analysis results

All five trace runs had the same alarm CSV and the same byte sequence from the observer that emitted reached statement IDs and printed joined cvalue states after the return statement of every defined function. The observer recorded 4,806 reached IDs and 109 exit queries, including bottom where applicable. This query scope includes definitions in the Frama-C libc. The hashes and loop iterations appear in [gzip.tsv](gzip.tsv). The different result at a single call precedes those joins. An alarm or a reachability decision sensitive to that value could in principle differ in another program. We did not observe such a difference here, compare every callstack state, or establish which return value is sound.

## Other targets and benchmark interpretation

[Archived comparisons](archived-comparison.tsv) compare sorted per-function memexec hit/miss rows, the alarm count and statement-coverage statistic from the allocation campaign with the heap and entry campaigns. Each comparison covers all 1,256 cases. Only gzip differed. The campaigns used different instrumentation or enabled counters. [Fresh comparisons](other-targets.tsv) use the allocation-counter binary on eight additional targets exercising free. Each target ran twice with default settings and once with a 64k-word minor heap. These finite comparisons establish the observed repeatability on the inputs tested.

For stage one, keep the pinned legacy memexec run and record its observed counts. Explain a missing hit at call level, including changes to the parent path. If a conclusion depends on a few hits here, repeat the baseline or use a separately labelled stable-order control. A blanket numerical tolerance would hide real regressions. Keep elapsed time descriptive when workloads differ. The unpatched gzip case executes allocation and free and is outside the allocation-free benchmark set. A static-pool variant needs its own measurements. Keep the new cache's accepted oldest-match rule, correctness comparisons to caching disabled, and per-entry accounting on reload. A joined exit match does not justify ignoring a difference in an individual call.

## Replaying the diagnostic

Use the allocation-counter [setup](../allocation-builtins/README.md) to prepare the analyzer source and case studies at the revisions above. Apply its [measurement patch](../allocation-builtins/measurement.patch) and then **one** of [trace.patch](trace.patch) or [detail.patch](detail.patch) to the analyzer with `patch -p1`. Trace reproduces the comparison procedure, detail also prints the two candidate states at lookup 5,276. The observer can affect the GC schedule. Exact choices under first-visited selection depend on the build and runtime.

Activate the checkout's OCaml switch and Python tool path. From the temporary analyzer source, with absolute paths for the case studies, script, and a fresh output directory, run:

```sh
dune build -j 8 @install
CASES=/path/to/case-studies OUT=/tmp/gzip-replay \
  dune exec --no-build -- bash /path/to/replay.sh first small oldest oldest-small newest
```

For the eight-target control use the allocation-counter build without either trace patch. In the build's Dune environment, export `EVA_WAYFINDER_HEAP_LOG` to a fresh absolute filename and run the following command for each target in the table, in a scratch copy of the pinned case studies. Run twice with default GC settings, then with `OCAMLRUNPARAM=s=64k`. Read `body_analysed` from the counter file and per-function memexec rows from the target's `eva-stats.csv`.

```sh
make -B -C "$CASES" "FRAMAC_DIR=$DUNE_SOURCEROOT/_build/install/default/bin" "$target"
```
