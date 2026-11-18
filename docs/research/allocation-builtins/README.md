# Allocation builtins applied per case-study target

Evidence for issue #28 ("Count the case-study targets in which no allocation
builtin runs"). This branch is never merged.

- Analyzer: this repository at `90a4b4cc53`, with `measurement.patch` applied.
  The patch is the instrumentation of the heap-refusal measurement (issue #14)
  plus a counter in `plugins/eva/src/utils/wayfinder_heap.ml`. The counter
  records each call by called function and target (builtin, specification or
  body), and each builtin application by name, just before
  `Builtins.apply_builtin` in `compute_builtin`
  (`plugins/eva/src/engine/compute_functions.ml`). It is active only when
  `EVA_WAYFINDER_HEAP_LOG` names an output file. The entry instrumentation in
  the patch stays off because `EVA_WAYFINDER_ENTRY_LOG` is unset.
- Case studies: `nyandrianinamamy/open-source-case-studies` at `168321b6`.
  The run used the local commit `3dcefdb6`, which only adds `AGENTS.md` and
  `stage1-pilot.sh`. `manifest.tsv` lists the 1,256 targets of the root
  `display-targets` recipe, in the order they were run.

## Files

- `per-target.tsv`: one row per target. `in_A` is true when no allocation
  builtin (`malloc`, `calloc`, `realloc`, `reallocarray`, `alloca`,
  `__fc_vla_alloc`) and no `free` builtin (`free`, `__fc_vla_free`) was
  applied. `alloc_only_A` ignores `free`; `in_A_strict` also excludes
  `Frama_C_check_leak`. `bodies` and `cpu` are the body analyses and the
  Eva analysis CPU seconds of the instrumented run. `tag` is the
  `*_DYN_ALLOC` tag of the directory's `OSCS-README.txt`.
- `controls/`: one small program per builtin, and `results.txt` with the
  counter output of each.
- `gzip124-runs.tsv`: body counts of `gzip124/gzip124.eva` in three runs.
- `run-campaign.sh`, `env.sh`, `summarize.py`: the scripts used, with
  local paths replaced by the variables `W28` and `FRAMA_C_CHECKOUT`.

## Replay

1. `git archive 90a4b4cc53 | tar -x -C "$W28/frama-c"`, then
   `patch -p1 < measurement.patch` in `$W28/frama-c`.
2. Extract the case studies at `168321b6` into `$W28/oscs`.
3. With the local opam switch of a checkout of this repository active, run
   `dune build -j 8 @install` in `$W28/frama-c`.
4. `W28=... FRAMA_C_CHECKOUT=... bash run-campaign.sh manifest.tsv "$W28/campaign"`.
   Runs are serial, with a 3,600 s limit each.
5. `python3 -I summarize.py "$W28/campaign" "$W28/oscs" - "$W28/summary"`.
   The third argument may instead name the per-target results of the
   heap-refusal measurement, to cross-check bodies and heap bases.

Counts are builtin applications with memexec on: a memexec hit replays a
stored entry without applying the builtins inside it.
