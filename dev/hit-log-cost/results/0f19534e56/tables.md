# Tables of the campaign

| what | value |
|---|---|
| branch | ab57e8e3aa7a20ae20c8afc5cc3b74a3d437e1bf |
| dev | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 |
| measure | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 |
| oscs | 3dcefdb6a33cad61a616321c5095ac1a51f4008f |
| cpu | 4	 Intel(R) Core(TM) i5-14600KF |
| perf | --call-graph dwarf,16384, perf script --max-stack 4096 |
| programs | gzip:3:3:3:3:all:99 monocypher:3:3:3:3:all:25 |
| ablations | footprint projection call-starts hits legacy walk zone-bases |
| cache | -cache-size 8 (share/analysis-scripts/analysis.mk:125) |
| built | 2026-11-22T21:00:11+01:00 |

Times in seconds, median of the runs, [min–max] across the runs; n is the number of successful runs, followed by the number expected when it is smaller. CPU is user + system time. Processor time of the phases from `Sys.time`. The revision and the cache size of each run are in the last table.

## 1. Wall-clock and processor time

| program | configuration | n | wall | CPU | peak RSS (MiB) | major faults (max) |
|---|---|---|---|---|---|---|
| gzip | dev | 3 | 74.1 [73.9–74.2] | 74.1 [73.9–74.2] | 842 | 0 |
| gzip | branch, recording off | 3 | 89.0 [88.9–89.1] | 89.0 [88.9–89.0] | 952 | 0 |
| gzip | branch, recording on | 3 | 104.3 [104.2–104.5] | 104.3 [104.2–104.5] | 1213 | 0 |
| monocypher | dev | 3 | 197.6 [197.0–198.2] | 197.5 [197.0–198.1] | 3617 | 0 |
| monocypher | branch, recording off | 3 | 199.3 [199.2–200.6] | 199.3 [199.2–200.5] | 3476 | 0 |
| monocypher | branch, recording on | 3 | 243.6 [243.6–243.9] | 243.5 [243.5–243.8] | 6529 | 0 |

Cache size of these runs: 8.

| program | on − off, wall | on − off, CPU | on − off, iteration | on − off, after iteration | off − dev, wall | off − dev, CPU | off − dev, iteration |
|---|---|---|---|---|---|---|---|
| gzip | 15.2 | 15.2 | 8.1 | 7.2 | 15.0 | 14.9 | 14.3 |
| monocypher | 44.3 | 44.2 | 22.1 | 22.2 | 1.8 | 1.8 | 1.7 |

Cache size of these runs: 8.

## 2. Phases, from the probe

parsing: from the load of the probe to the AST; preparation: to the start of the iteration (state Computing); iteration: to its end (state Computed), the initial state of the globals included; after iteration: the passes, up to the end of the main function of Eva; exit: to the exit of the process.

| program | configuration | parsing (wall) | preparation (wall) | iteration (wall) | after iteration (wall) | exit (wall) | iteration (CPU) |
|---|---|---|---|---|---|---|---|
| gzip | dev | 0.99 [0.99–1.02] | 0.02 [0.02–0.02] | 71.54 [71.32–71.67] | 1.47 [1.47–1.48] | 0.00 [0.00–0.00] | 71.53 [71.30–71.65] |
| gzip | branch, recording off | 0.98 [0.98–0.99] | 0.02 [0.02–0.02] | 85.88 [85.81–85.93] | 2.05 [2.05–2.08] | 0.00 [0.00–0.00] | 85.86 [85.78–85.91] |
| gzip | branch, recording on | 0.99 [0.98–1.00] | 0.02 [0.02–0.02] | 93.98 [93.88–94.16] | 9.25 [9.21–9.26] | 0.00 [0.00–0.00] | 93.95 [93.86–94.14] |
| monocypher | dev | 2.85 [2.80–2.86] | 0.03 [0.03–0.03] | 188.48 [187.91–189.02] | 6.08 [6.08–6.17] | 0.00 [0.00–0.00] | 188.43 [187.85–188.97] |
| monocypher | branch, recording off | 2.80 [2.79–2.82] | 0.03 [0.03–0.03] | 190.20 [190.11–191.47] | 6.15 [6.09–6.17] | 0.00 [0.00–0.00] | 190.15 [190.05–191.41] |
| monocypher | branch, recording on | 2.81 [2.81–2.82] | 0.03 [0.03–0.03] | 212.34 [211.95–212.46] | 28.39 [28.19–28.56] | 0.00 [0.00–0.00] | 212.27 [211.85–212.40] |

Cache size of these runs: 8.

## 3. Steps after the iteration, measurement build with timers

Wall-clock time of each step of `post_analysis` and of the hooks of state Computed. 'initial state' is the computation of the initial state of the globals, inside the iteration of table 2. 'consolidation' runs with recording off only.

### gzip (n = 3 off, 3 on)

| step | off | on | on − off |
|---|---|---|---|
| initial state | 0.095 [0.095–0.095] | 0.096 [0.096–0.096] | 0.001 |
| computed hooks | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| garbled mix | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| unreachable statements | 0.089 [0.088–0.091] | 3.191 [3.081–3.204] | 3.102 |
| statuses of the properties | 0.027 [0.026–0.028] | 4.613 [3.834–4.642] | 4.587 |
| memexec cleanup | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| redundant alarms | 1.034 [1.017–1.039] | 1.091 [1.089–1.093] | 0.057 |
| statistics | 0.006 [0.006–0.006] | 0.007 [0.007–0.007] | 0.001 |
| red statuses | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| consolidation | 0.070 [0.069–0.070] | – | -0.070 |
| final values | 0.293 [0.291–0.294] | 0.287 [0.286–0.291] | -0.006 |
| domains | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| summary | 0.005 [0.005–0.005] | 0.006 [0.005–0.006] | 0.000 |
| statistics export | 0.552 [0.552–0.555] | 1.050 [0.914–1.057] | 0.498 |

Cache size of these runs: 8.

### monocypher (n = 3 off, 3 on)

| step | off | on | on − off |
|---|---|---|---|
| initial state | 9.973 [9.938–9.973] | 9.985 [9.935–10.000] | 0.012 |
| computed hooks | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| garbled mix | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| unreachable statements | 0.426 [0.424–0.430] | 8.637 [8.629–8.670] | 8.211 |
| statuses of the properties | 0.059 [0.059–0.060] | 12.911 [12.671–12.995] | 12.852 |
| memexec cleanup | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| redundant alarms | 1.603 [1.603–1.645] | 1.715 [1.702–1.731] | 0.111 |
| statistics | 0.002 [0.002–0.002] | 0.004 [0.004–0.004] | 0.002 |
| red statuses | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| consolidation | 0.358 [0.355–0.391] | – | -0.358 |
| final values | 1.228 [1.210–1.243] | 1.237 [1.235–1.241] | 0.009 |
| domains | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| summary | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | 0.000 |
| statistics export | 2.613 [2.484–2.621] | 4.177 [4.173–4.180] | 1.564 |

Cache size of these runs: 8.

## 4. Parts of the iteration, measurement build with timers

Exclusive wall-clock time of each part (a part nested in another is counted in the inner one only), median of the runs. The parts are those of the timers file. 'rest' is the iteration of the probe minus the parts. The remainder is the difference of the iteration minus the differences of the parts, that is the difference of the rest. The parts account for the difference within the tolerance if the remainder is at most 10 % of the difference of the iteration, or at most the largest range of the iteration across the runs of either mode if that is larger.

### gzip (n = 3 off, 3 on)

| part | off | on | on − off | calls (on) |
|---|---|---|---|---|
| merge | 1.17 | 1.47 | 0.30 | 9005 |
| legacy store | 1.19 | 1.37 | 0.18 | 98247 |
| hooks | 9.49 | 9.94 | 0.45 | 9005 |
| footprint | 0.00 | 0.45 | 0.45 | 881221 |
| point projection | 0.00 | 1.77 | 1.77 | 18010 |
| call starts | 0.00 | 0.39 | 0.39 | 187489 |
| hits and starts | 0.00 | 0.45 | 0.45 | 258721 |
| memexec | 1.17 | 1.27 | 0.10 | 81573 |
| created and removed walk | 0.00 | 1.07 | 1.07 | 959403 |
| zone bases | 0.00 | 2.62 | 2.62 | 959403 |
| sum of the parts | 13.02 | 20.80 | 7.78 |  |
| rest of the iteration | 72.56 | 73.12 | 0.56 |  |
| iteration | 85.72 | 93.81 | 8.09 |  |

Cache size of these runs: 8.

Difference of the iteration: 8.09 s; of the parts: 7.78 s; remainder: 0.31 s (3.9 % of the difference); tolerance: 0.86 s; within the tolerance: yes.

### monocypher (n = 3 off, 3 on)

| part | off | on | on − off | calls (on) |
|---|---|---|---|---|
| merge | 5.05 | 5.31 | 0.26 | 61331 |
| legacy store | 7.28 | 4.76 | -2.52 | 767333 |
| hooks | 19.14 | 20.20 | 1.05 | 61331 |
| footprint | 0.00 | 0.57 | 0.57 | 1889394 |
| point projection | 0.00 | 1.82 | 1.82 | 122662 |
| call starts | 0.00 | 2.46 | 2.46 | 1473335 |
| hits and starts | 0.00 | 1.57 | 1.57 | 2056675 |
| memexec | 2.95 | 2.79 | -0.16 | 765579 |
| created and removed walk | 0.00 | 3.23 | 3.23 | 2585779 |
| zone bases | 0.00 | 4.01 | 4.01 | 2585779 |
| sum of the parts | 34.42 | 46.72 | 12.30 |  |
| rest of the iteration | 159.12 | 166.76 | 7.64 |  |
| iteration | 193.52 | 213.56 | 20.04 |  |

Cache size of these runs: 8.

Difference of the iteration: 20.04 s; of the parts: 12.30 s; remainder: 7.74 s (38.6 % of the difference); tolerance: 2.19 s; within the tolerance: NO.

## 5. Garbage collector, from the probe

Counters of `Gc.quick_stat` over the phase, median of the runs; words in millions; the top heap is the largest size of the major heap. The time spent in the collector is in table 6.

| program | configuration | phase | minor_words | promoted_words | major_words | minor_collections | major_collections |
|---|---|---|---|---|---|---|---|
| gzip | dev | iteration | 18150 | 251 | 286 | 69245 | 12 |
| gzip | dev | after iteration | 407 | 3 | 4 | 1557 | 3 |
| gzip | dev | top heap (MiB) | 791 |  |  |  |  |
| gzip | branch, recording off | iteration | 21256 | 292 | 330 | 81092 | 13 |
| gzip | branch, recording off | after iteration | 702 | 4 | 6 | 2685 | 3 |
| gzip | branch, recording off | top heap (MiB) | 894 |  |  |  |  |
| gzip | branch, recording on | iteration | 24493 | 343 | 393 | 93443 | 13 |
| gzip | branch, recording on | after iteration | 4821 | 24 | 30 | 18398 | 3 |
| gzip | branch, recording on | top heap (MiB) | 1152 |  |  |  |  |
| monocypher | dev | iteration | 58137 | 865 | 1063 | 221803 | 12 |
| monocypher | dev | after iteration | 1275 | 8 | 10 | 4869 | 3 |
| monocypher | dev | top heap (MiB) | 3560 |  |  |  |  |
| monocypher | branch, recording off | iteration | 58178 | 864 | 1060 | 221959 | 12 |
| monocypher | branch, recording off | after iteration | 1285 | 9 | 10 | 4906 | 3 |
| monocypher | branch, recording off | top heap (MiB) | 3417 |  |  |  |  |
| monocypher | branch, recording on | iteration | 64060 | 1007 | 1268 | 244396 | 11 |
| monocypher | branch, recording on | after iteration | 5761 | 209 | 223 | 21981 | 3 |
| monocypher | branch, recording on | top heap (MiB) | 6467 |  |  |  |  |

Cache size of these runs: 8.

## 6. Profiles, perf

### gzip

Seconds = samples / frequency. GC: chains through the minor collection, through the major slices, and allocation in the major heap outside a collection. Chains: % reaching `caml_start_program`, and % stopping at a switch to the C stack (`caml_call_gc`, `caml_c_call`): the OCaml callers of those samples are unknown, so the inclusive time of an OCaml function excludes the GC and the C primitives it calls.

| window | mode | CPU (s) | minor GC | major GC | major alloc. | other runtime | complete % | C stack % |
|---|---|---|---|---|---|---|---|---|
| iteration | off | 86.5 | 2.2 | 6.0 | 0.3 | 0.1 | 81 | 9 |
| iteration | on | 94.5 | 2.3 | 7.5 | 0.2 | 0.0 | 80 | 10 |
| after iteration | off | 1.5 | 0.1 | 0.2 | 0.0 | 0.0 | 75 | 13 |
| after iteration | on | 9.8 | 0.2 | 1.9 | 0.0 | 0.0 | 73 | 21 |

Cache size of these runs: 8.

Top 20 differences of own time, iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `Stdlib.Weak.find_aux_780` | 4.79 | 6.35 | 1.57 |
| 2 | `caml_apply2` | 7.05 | 7.59 | 0.54 |
| 3 | `Frama_c_kernel_base.Base.id_2655` | 0.28 | 0.63 | 0.34 |
| 4 | `Stdlib.Weak.loop_791` | 1.31 | 1.64 | 0.32 |
| 5 | `Fclib.Hptmap.hash_internal_4489` | 0.18 | 0.46 | 0.28 |
| 6 | `Fclib.Hptmap.merge_5180` | 0.09 | 0.35 | 0.26 |
| 7 | `Fclib.Hptmap.aux_1944` | 0.02 | 0.26 | 0.24 |
| 8 | `Fclib.Hptmap.from_shape_4862` | 0.02 | 0.22 | 0.20 |
| 9 | `caml_c_call` | 0.27 | 0.46 | 0.19 |
| 10 | `caml_darken` | 2.29 | 2.48 | 0.19 |
| 11 | `ephe_get_field` | 0.30 | 0.49 | 0.19 |
| 12 | `Stdlib.Map.bal_406` | 0.32 | 0.14 | -0.18 |
| 13 | `caml_apply4` | 0.45 | 0.27 | -0.18 |
| 14 | `pool_sweep` | 0.36 | 0.55 | 0.18 |
| 15 | `Stdlib.Hashtbl.find_1111` | 1.81 | 1.98 | 0.17 |
| 16 | `caml_alloc_small` | 0.15 | 0.32 | 0.17 |
| 17 | `clean_field` | 0.09 | 0.26 | 0.17 |
| 18 | `Eva.Partition.compare_7509` | 0.19 | 0.03 | -0.16 |
| 19 | `caml_tuplify2` | 0.26 | 0.42 | 0.16 |
| 20 | `Fclib.Hptmap.fold_1620` | 0.23 | 0.37 | 0.14 |

Cache size of these runs: 8.

Top 20 differences of inclusive time, iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `Eva.Hit_log.call_5640` | 0.00 | 75.92 | 75.92 |
| 2 | `Eva.Iterator.merge_results_8376` | 1.37 | 9.63 | 8.25 |
| 3 | `Eva.Hit_log.footprint_of_call_5039` | 0.00 | 7.96 | 7.96 |
| 4 | `Dune.exe.Entry_point.entry` | 69.97 | 75.95 | 5.98 |
| 5 | `Eva.Analysis.fun_13299` | 69.97 | 75.95 | 5.98 |
| 6 | `Fclib.State_builder.fun_12593` | 69.97 | 75.95 | 5.98 |
| 7 | `Frama_c_kernel_base.Boot.play_analysis_579` | 69.97 | 75.95 | 5.98 |
| 8 | `Frama_c_kernel_base.Cmdline.catch_toplevel_run_2072` | 69.97 | 75.95 | 5.98 |
| 9 | `Frama_c_kernel_base.Cmdline.play_in_toplevel_3280` | 69.97 | 75.95 | 5.98 |
| 10 | `Frama_c_kernel_base.Cmdline.play_in_toplevel_one_shot_3263` | 69.97 | 75.95 | 5.98 |
| 11 | `Stdlib.Fun.protect_326` | 69.97 | 75.95 | 5.98 |
| 12 | `Stdlib.List.fold_left_380` | 69.97 | 75.95 | 5.98 |
| 13 | `Stdlib.Queue.iter_332` | 69.97 | 75.95 | 5.98 |
| 14 | `caml_program` | 69.97 | 75.95 | 5.98 |
| 15 | `caml_start_program` | 69.97 | 75.95 | 5.98 |
| 16 | `Eva.Compute_functions.compute_and_cache_call_4075` | 69.95 | 75.92 | 5.97 |
| 17 | `Eva.Compute_functions.compute_using_spec_or_body_5494` | 69.95 | 75.92 | 5.97 |
| 18 | `Eva.Compute_functions.fun_6942` | 69.95 | 75.92 | 5.97 |
| 19 | `Eva.Iterator.compute_10790` | 69.95 | 75.92 | 5.97 |
| 20 | `Eva.Iterator.compute_8343` | 69.95 | 75.92 | 5.97 |

Cache size of these runs: 8.

Top 20 differences of own time, after iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `Stdlib.Weak.find_aux_780` | 0.15 | 1.93 | 1.78 |
| 2 | `ephe_mark` | 0.00 | 0.59 | 0.59 |
| 3 | `Stdlib.Weak.loop_791` | 0.06 | 0.47 | 0.41 |
| 4 | `Fclib.Hptmap.from_shape_4862` | 0.00 | 0.35 | 0.35 |
| 5 | `Fclib.Hptmap.merge_5048` | 0.00 | 0.29 | 0.29 |
| 6 | `Frama_c_kernel_base.Base.id_2655` | 0.00 | 0.26 | 0.26 |
| 7 | `caml_apply2` | 0.12 | 0.38 | 0.26 |
| 8 | `caml_darken` | 0.09 | 0.32 | 0.23 |
| 9 | `ephe_get_field` | 0.02 | 0.21 | 0.19 |
| 10 | `Fclib.Hptmap.hash_internal_4489` | 0.00 | 0.16 | 0.16 |
| 11 | `caml_ephe_clean.part.0` | 0.00 | 0.16 | 0.16 |
| 12 | `Stdlib.Hashtbl.find_opt_1130` | 0.00 | 0.15 | 0.15 |
| 13 | `Stdlib.Weak.add_aux_745` | 0.02 | 0.14 | 0.12 |
| 14 | `Fclib.Hptmap.wrap_Branch_4709` | 0.00 | 0.11 | 0.11 |
| 15 | `Fclib.Hptmap.compositional_bool_2352` | 0.00 | 0.10 | 0.10 |
| 16 | `Stdlib.List.iter_366` | 0.00 | 0.09 | 0.09 |
| 17 | `caml_apply3` | 0.03 | 0.12 | 0.09 |
| 18 | `Stdlib.Weak.merge_805` | 0.00 | 0.08 | 0.08 |
| 19 | `caml_next_frame_descriptor` | 0.01 | 0.09 | 0.08 |
| 20 | `caml_shared_try_alloc` | 0.00 | 0.08 | 0.08 |

Cache size of these runs: 8.

Top 20 differences of inclusive time, after iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `Dune.exe.Entry_point.entry` | 1.13 | 7.17 | 6.04 |
| 2 | `Eva.Analysis.fun_13299` | 1.13 | 7.17 | 6.04 |
| 3 | `Eva.Analysis.post_analysis_7563` | 1.13 | 7.17 | 6.04 |
| 4 | `Fclib.State_builder.fun_12593` | 1.13 | 7.17 | 6.04 |
| 5 | `Frama_c_kernel_base.Boot.play_analysis_579` | 1.13 | 7.17 | 6.04 |
| 6 | `Frama_c_kernel_base.Cmdline.catch_toplevel_run_2072` | 1.13 | 7.17 | 6.04 |
| 7 | `Frama_c_kernel_base.Cmdline.play_in_toplevel_3280` | 1.13 | 7.17 | 6.04 |
| 8 | `Frama_c_kernel_base.Cmdline.play_in_toplevel_one_shot_3263` | 1.13 | 7.17 | 6.04 |
| 9 | `Stdlib.Fun.protect_326` | 1.13 | 7.17 | 6.04 |
| 10 | `Stdlib.Queue.iter_332` | 1.13 | 7.17 | 6.04 |
| 11 | `caml_program` | 1.13 | 7.17 | 6.04 |
| 12 | `caml_start_program` | 1.13 | 7.17 | 6.04 |
| 13 | `Eva.Hit_log.count_pastes_6353` | 0.00 | 5.92 | 5.92 |
| 14 | `Stdlib.List.iter_366` | 0.32 | 6.22 | 5.90 |
| 15 | `Stdlib.List.fold_left_380` | 0.90 | 4.97 | 4.07 |
| 16 | `Eva.Engine.get_13222` | 0.00 | 3.69 | 3.69 |
| 17 | `Eva.Hit_log.fun_7266` | 0.00 | 3.62 | 3.62 |
| 18 | `Eva.Results.fun_9766` | 0.05 | 3.29 | 3.24 |
| 19 | `Eva.Hit_log.memo_6588` | 0.00 | 3.15 | 3.15 |
| 20 | `Eva.Hit_log.point_state_6572` | 0.00 | 3.14 | 3.14 |

Cache size of these runs: 8.

### monocypher

Seconds = samples / frequency. GC: chains through the minor collection, through the major slices, and allocation in the major heap outside a collection. Chains: % reaching `caml_start_program`, and % stopping at a switch to the C stack (`caml_call_gc`, `caml_c_call`): the OCaml callers of those samples are unknown, so the inclusive time of an OCaml function excludes the GC and the C primitives it calls.

| window | mode | CPU (s) | minor GC | major GC | major alloc. | other runtime | complete % | C stack % |
|---|---|---|---|---|---|---|---|---|
| iteration | off | 192.2 | 5.3 | 16.1 | 1.1 | 0.0 | 78 | 13 |
| iteration | on | 212.8 | 5.7 | 22.4 | 1.4 | 0.2 | 75 | 16 |
| after iteration | off | 3.6 | 0.1 | 0.2 | 0.0 | 0.0 | 79 | 4 |
| after iteration | on | 24.3 | 1.1 | 5.4 | 0.0 | 0.0 | 68 | 24 |

Cache size of these runs: 8.

Top 20 differences of own time, iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `ephe_mark` | 3.80 | 8.24 | 4.44 |
| 2 | `caml_apply2` | 14.04 | 16.84 | 2.80 |
| 3 | `Stdlib.Weak.find_aux_780` | 12.24 | 14.04 | 1.80 |
| 4 | `Stdlib.Weak.loop_769` | 0.96 | 1.76 | 0.80 |
| 5 | `caml_hash` | 2.12 | 2.88 | 0.76 |
| 6 | `pool_sweep` | 1.12 | 1.76 | 0.64 |
| 7 | `Fclib.Hptmap.merge_5180` | 0.12 | 0.64 | 0.52 |
| 8 | `Z.add_283` | 0.88 | 0.36 | -0.52 |
| 9 | `caml_shared_try_alloc` | 1.04 | 1.56 | 0.52 |
| 10 | `do_some_marking` | 1.04 | 1.56 | 0.52 |
| 11 | `Fclib.Binary_cache.get0_543` | 1.28 | 1.76 | 0.48 |
| 12 | `Frama_c_kernel_base.Base.id_2655` | 0.76 | 1.24 | 0.48 |
| 13 | `ml_z_compare` | 0.88 | 1.36 | 0.48 |
| 14 | `Eva.Partition.compare_7509` | 0.60 | 0.16 | -0.44 |
| 15 | `Fclib.State_builder.merge_4761` | 0.52 | 0.12 | -0.40 |
| 16 | `Stdlib.Hashtbl.find_opt_1130` | 0.00 | 0.40 | 0.40 |
| 17 | `Stdlib.Map.find_448` | 0.76 | 1.16 | 0.40 |
| 18 | `caml_stash_backtrace` | 0.80 | 1.20 | 0.40 |
| 19 | `caml_string_compare` | 0.16 | 0.56 | 0.40 |
| 20 | `Eva.Main_locations.forward_variable_3741` | 0.00 | 0.36 | 0.36 |

Cache size of these runs: 8.

Top 20 differences of inclusive time, iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `Eva.Hit_log.call_5640` | 0.00 | 153.48 | 153.48 |
| 2 | `Eva.Iterator.merge_results_8376` | 5.12 | 23.00 | 17.88 |
| 3 | `Eva.Hit_log.footprint_of_call_5039` | 0.00 | 15.56 | 15.56 |
| 4 | `Eva.Compute_functions.compute_and_cache_call_4075` | 142.80 | 153.48 | 10.68 |
| 5 | `Eva.Compute_functions.compute_using_spec_or_body_5494` | 142.80 | 153.48 | 10.68 |
| 6 | `Eva.Compute_functions.fun_6942` | 142.80 | 153.48 | 10.68 |
| 7 | `Eva.Iterator.compute_10790` | 142.80 | 153.48 | 10.68 |
| 8 | `Eva.Signal.protect_1058` | 142.80 | 153.48 | 10.68 |
| 9 | `Eva.Iterator.compute_8343` | 142.80 | 153.24 | 10.44 |
| 10 | `Eva.Iterator.fun_12810` | 142.80 | 153.24 | 10.44 |
| 11 | `Eva.Iterator.iterate_element_8051` | 142.80 | 153.24 | 10.44 |
| 12 | `Eva.Iterator.process_source_7978` | 142.80 | 153.24 | 10.44 |
| 13 | `Eva.Iterator.process_vertex_inner_12905` | 142.80 | 153.24 | 10.44 |
| 14 | `Eva.Iterator.transfer_call_6710` | 142.80 | 153.24 | 10.44 |
| 15 | `Eva.Partition.fun_12325` | 142.80 | 153.24 | 10.44 |
| 16 | `Eva.Transfer_stmt.do_one_call_7294` | 142.80 | 153.24 | 10.44 |
| 17 | `Eva.Transfer_stmt.process_9434` | 142.80 | 153.24 | 10.44 |
| 18 | `Eva.Transfer_stmt.process_one_function_9304` | 142.80 | 153.24 | 10.44 |
| 19 | `Stdlib.List.concat_map_583` | 142.80 | 153.24 | 10.44 |
| 20 | `Stdlib.List.iter_366` | 142.80 | 153.24 | 10.44 |

Cache size of these runs: 8.

Top 20 differences of own time, after iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `ephe_mark` | 0.00 | 3.44 | 3.44 |
| 2 | `Stdlib.Hashtbl.find_opt_1130` | 0.00 | 2.84 | 2.84 |
| 3 | `Stdlib.Weak.find_aux_780` | 0.20 | 2.84 | 2.64 |
| 4 | `Stdlib.Hashtbl.key_index_1080` | 0.12 | 1.32 | 1.20 |
| 5 | `caml_darken` | 0.16 | 0.96 | 0.80 |
| 6 | `Stdlib.Weak.loop_791` | 0.00 | 0.68 | 0.68 |
| 7 | `Eva.Callstack.equal_3246` | 0.00 | 0.52 | 0.52 |
| 8 | `caml_apply2` | 0.36 | 0.76 | 0.40 |
| 9 | `oldify_one` | 0.04 | 0.44 | 0.40 |
| 10 | `Eva.Callstack.loop_3253` | 0.00 | 0.36 | 0.36 |
| 11 | `Fclib.Hptmap.from_shape_4862` | 0.00 | 0.36 | 0.36 |
| 12 | `Fclib.Hptmap.merge_5048` | 0.08 | 0.44 | 0.36 |
| 13 | `caml_hash` | 0.00 | 0.36 | 0.36 |
| 14 | `Frama_c_kernel_base.Base.id_2655` | 0.00 | 0.32 | 0.32 |
| 15 | `Frama_c_kernel_base.Cil_datatype.id_45913` | 0.00 | 0.28 | 0.28 |
| 16 | `ephe_get_field` | 0.00 | 0.28 | 0.28 |
| 17 | `Fclib.Binary_cache.get0_543` | 0.00 | 0.24 | 0.24 |
| 18 | `Stdlib.Hashtbl.find_rec_opt_1124` | 0.00 | 0.20 | 0.20 |
| 19 | `Stdlib.List.filter_map_dps_1182` | 0.00 | 0.20 | 0.20 |
| 20 | `caml_shared_try_alloc` | 0.04 | 0.24 | 0.20 |

Cache size of these runs: 8.

Top 20 differences of inclusive time, after iteration (s), on − off:

| # | function | off | on | on − off |
|---|---|---|---|---|
| 1 | `Eva.Hit_log.count_pastes_6353` | 0.00 | 14.16 | 14.16 |
| 2 | `Stdlib.List.iter_366` | 2.36 | 16.16 | 13.80 |
| 3 | `Dune.exe.Entry_point.entry` | 2.88 | 16.52 | 13.64 |
| 4 | `Eva.Analysis.fun_13299` | 2.88 | 16.52 | 13.64 |
| 5 | `Eva.Analysis.post_analysis_7563` | 2.88 | 16.52 | 13.64 |
| 6 | `Fclib.State_builder.fun_12593` | 2.88 | 16.52 | 13.64 |
| 7 | `Frama_c_kernel_base.Boot.play_analysis_579` | 2.88 | 16.52 | 13.64 |
| 8 | `Frama_c_kernel_base.Cmdline.catch_toplevel_run_2072` | 2.88 | 16.52 | 13.64 |
| 9 | `Frama_c_kernel_base.Cmdline.play_in_toplevel_3280` | 2.88 | 16.52 | 13.64 |
| 10 | `Frama_c_kernel_base.Cmdline.play_in_toplevel_one_shot_3263` | 2.88 | 16.52 | 13.64 |
| 11 | `Stdlib.Fun.protect_326` | 2.88 | 16.52 | 13.64 |
| 12 | `Stdlib.Queue.iter_332` | 2.88 | 16.52 | 13.64 |
| 13 | `caml_program` | 2.88 | 16.52 | 13.64 |
| 14 | `caml_start_program` | 2.88 | 16.52 | 13.64 |
| 15 | `Eva.Engine.get_13222` | 0.00 | 12.76 | 12.76 |
| 16 | `Eva.Hit_log.fun_7266` | 0.00 | 12.72 | 12.72 |
| 17 | `Eva.Hit_log.point_state_6572` | 0.00 | 10.96 | 10.96 |
| 18 | `Stdlib.List.fold_left_380` | 1.92 | 12.04 | 10.12 |
| 19 | `Stdlib.List.map_dps_1255` | 0.00 | 9.04 | 9.04 |
| 20 | `Stdlib.List.map_333` | 1.04 | 10.00 | 8.96 |

Cache size of these runs: 8.

## 7. Ablations, measurement build with timers, recording on

Each ablation skips one part of the recording; its answers are wrong, so only the iteration counts. Upper bound of the saving = median iteration of the run it is taken against minus median iteration of the ablation: the control (recording on, no ablation), or, for an ablation A+B, the runs of ablation A, so that the bound of B is its saving once A is removed. The range of the bound goes from the smallest to the largest difference between a run it is taken against and a run of the ablation; a bound whose range includes 0 is not told apart from the noise. The hits, the calls analysed by their body (memexec misses) and the alarms come from `-eva-statistics-file`; 'same' compares them with the control.

### gzip

| ablation | against | n | iteration | upper bound (iteration) | above the noise | wall | saving (wall) | same hits, analysed, alarms |
|---|---|---|---|---|---|---|---|---|
| control |  | 3 | 93.8 [93.6–94.5] |  |  | 105.0 |  |  |
| footprint | control | 3 | 88.5 [88.4–89.3] | 5.3 [4.4–6.1] | yes | 95.3 | 9.7 | yes |
| projection | control | 3 | 88.3 [88.3–88.3] | 5.5 [5.3–6.3] | yes | 90.3 | 14.7 | NO |
| call-starts | control | 3 | 93.4 [92.9–93.8] | 0.4 [-0.1–1.6] | no | 102.0 | 3.0 | yes |
| hits | control | 3 | 92.7 [92.7–93.0] | 1.1 [0.6–1.8] | yes | 100.5 | 4.5 | yes |
| legacy | control | 3 | 92.9 [92.7–93.2] | 0.9 [0.5–1.8] | yes | 104.7 | 0.3 | yes |
| walk | control | 3 | 92.2 [92.2–92.5] | 1.6 [1.1–2.3] | yes | 102.8 | 2.2 | NO |
| zone-bases | control | 3 | 89.2 [89.0–89.3] | 4.6 [4.4–5.5] | yes | 96.1 | 8.9 | NO |

Cache size of these runs: 8.

### monocypher

| ablation | against | n | iteration | upper bound (iteration) | above the noise | wall | saving (wall) | same hits, analysed, alarms |
|---|---|---|---|---|---|---|---|---|
| control |  | 3 | 213.6 [212.9–213.6] |  |  | 245.0 |  |  |
| footprint | control | 3 | 199.2 [198.8–199.6] | 14.3 [13.3–14.8] | yes | 224.4 | 20.7 | yes |
| projection | control | 3 | 198.9 [198.6–199.3] | 14.6 [13.7–15.0] | yes | 205.3 | 39.8 | NO |
| call-starts | control | 3 | 202.8 [202.5–210.2] | 10.8 [2.7–11.1] | yes | 210.9 | 34.2 | yes |
| hits | control | 3 | 203.3 [202.8–204.7] | 10.3 [8.2–10.8] | yes | 221.6 | 23.4 | yes |
| legacy | control | 3 | 202.7 [202.6–203.0] | 10.8 [10.0–10.9] | yes | 232.3 | 12.7 | yes |
| walk | control | 3 | 209.8 [209.5–209.8] | 3.8 [3.2–4.1] | yes | 241.0 | 4.0 | yes |
| zone-bases | control | 3 | 200.3 [200.2–200.8] | 13.2 [12.1–13.4] | yes | 226.3 | 18.7 | yes |

Cache size of these runs: 8.

## 8. Hits

From one run with -eva-msg-key=progress per configuration, counted on the fly: hits, the messages 'Reusing old results for call to'; recorded, 'Recording results for' (calls analysed by their body, the main function included); computing, 'computing for function' (calls analysed by their body or their specification that are not hits). memexec hits and misses: sums of `-eva-statistics-file` over the functions, in the timed runs of the configuration (distinct values separated by /).

| program | configuration | hits | recorded | computing | memexec hits | memexec misses | iteration (s) | wall (s) |
|---|---|---|---|---|---|---|---|---|
| gzip | dev | 45778 | 5995 | 9878 | 45782 | 5991 | 71.5 | 74.1 |
| gzip | branch, recording off | 64529 | 9005 | 14565 | 64529 | 9005 | 85.9 | 89.0 |
| gzip | branch, recording on | 64529 | 9005 | 14565 | 64529 | 9005 | 94.0 | 104.3 |
| monocypher | dev | 643192 | 61309 | 62359 | 643192 | 61309 | 188.5 | 197.6 |
| monocypher | branch, recording off | 643170 | 61331 | 62381 | 643170 | 61331 | 190.2 | 199.3 |
| monocypher | branch, recording on | 643170 | 61331 | 62381 | 643170 | 61331 | 212.3 | 243.6 |

Cache size of these runs: 8.

## 9. Measurement build against the branch

branch: this checkout; plain: the measurement build with no variable set (timers off, no ablation); meter: the measurement build with the timers. Wall-clock time and iteration.

| program | recording | build | n | wall | iteration |
|---|---|---|---|---|---|
| gzip | off | branch | 3 | 89.0 [88.9–89.1] | 85.9 [85.8–85.9] |
| gzip | off | plain | 3 | 88.8 [88.5–88.8] | 85.7 [85.3–85.7] |
| gzip | off | meter | 3 | 88.9 [88.7–89.4] | 85.7 [85.5–86.2] |
| gzip | on | branch | 3 | 104.3 [104.2–104.5] | 94.0 [93.9–94.2] |
| gzip | on | plain | 3 | 104.9 [103.7–104.9] | 93.4 [93.2–93.6] |
| gzip | on | meter | 3 | 105.0 [104.8–105.2] | 93.8 [93.6–94.5] |
| monocypher | off | branch | 3 | 199.3 [199.2–200.6] | 190.2 [190.1–191.5] |
| monocypher | off | plain | 3 | 200.6 [200.4–200.9] | 191.5 [191.3–191.8] |
| monocypher | off | meter | 3 | 202.8 [200.5–202.9] | 193.5 [191.4–193.6] |
| monocypher | on | branch | 3 | 243.6 [243.6–243.9] | 212.3 [211.9–212.5] |
| monocypher | on | plain | 3 | 244.0 [243.9–245.8] | 212.5 [212.5–214.4] |
| monocypher | on | meter | 3 | 245.0 [244.7–245.5] | 213.6 [212.9–213.6] |

Cache size of these runs: 8.

## 10. Runs

Each run directory, with the revision of its build as noted when it was built, the cache size of its analyses, and its status.

| run | revision | cache size | status | wall |
|---|---|---|---|---|
| ablate-call-starts-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 102.6 |
| ablate-call-starts-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 101.5 |
| ablate-call-starts-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 102.0 |
| ablate-call-starts-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 218.4 |
| ablate-call-starts-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 210.9 |
| ablate-call-starts-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 210.6 |
| ablate-footprint-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 95.3 |
| ablate-footprint-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 96.1 |
| ablate-footprint-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 95.3 |
| ablate-footprint-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 224.5 |
| ablate-footprint-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 223.6 |
| ablate-footprint-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 224.4 |
| ablate-hits-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 100.8 |
| ablate-hits-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 100.5 |
| ablate-hits-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 100.5 |
| ablate-hits-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 223.1 |
| ablate-hits-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 220.8 |
| ablate-hits-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 221.6 |
| ablate-legacy-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 104.7 |
| ablate-legacy-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 105.0 |
| ablate-legacy-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 104.5 |
| ablate-legacy-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 232.3 |
| ablate-legacy-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 232.4 |
| ablate-legacy-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 232.2 |
| ablate-projection-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 90.3 |
| ablate-projection-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 90.3 |
| ablate-projection-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 90.2 |
| ablate-projection-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 205.3 |
| ablate-projection-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 205.4 |
| ablate-projection-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 204.8 |
| ablate-walk-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 103.7 |
| ablate-walk-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 102.8 |
| ablate-walk-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 102.5 |
| ablate-walk-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 241.1 |
| ablate-walk-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 240.9 |
| ablate-walk-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 241.0 |
| ablate-zone-bases-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 96.1 |
| ablate-zone-bases-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 96.1 |
| ablate-zone-bases-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 96.1 |
| ablate-zone-bases-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 226.9 |
| ablate-zone-bases-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 226.3 |
| ablate-zone-bases-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 226.3 |
| dev-gzip-1 | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | 74.2 |
| dev-gzip-2 | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | 74.1 |
| dev-gzip-3 | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | 73.9 |
| dev-monocypher-1 | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | 198.2 |
| dev-monocypher-2 | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | 197.0 |
| dev-monocypher-3 | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | 197.6 |
| hits-dev-gzip | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | – |
| hits-dev-monocypher | 375ab36aa5b3e254f6bf13860cb7641561a0c8c1 | 8 | 0 | – |
| hits-off-gzip | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | – |
| hits-off-monocypher | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | – |
| hits-on-gzip | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | – |
| hits-on-monocypher | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | – |
| meter-off-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 88.7 |
| meter-off-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 88.9 |
| meter-off-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 89.4 |
| meter-off-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 202.8 |
| meter-off-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 202.9 |
| meter-off-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 200.5 |
| meter-on-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 105.2 |
| meter-on-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 105.0 |
| meter-on-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 104.8 |
| meter-on-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 245.5 |
| meter-on-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 244.7 |
| meter-on-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 245.0 |
| off-gzip-1 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 88.9 |
| off-gzip-2 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 89.0 |
| off-gzip-3 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 89.1 |
| off-monocypher-1 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 200.6 |
| off-monocypher-2 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 199.3 |
| off-monocypher-3 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 199.2 |
| on-gzip-1 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 104.2 |
| on-gzip-2 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 104.5 |
| on-gzip-3 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 104.3 |
| on-monocypher-1 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 243.6 |
| on-monocypher-2 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 243.6 |
| on-monocypher-3 | c541d5425c884e5cc4eaa68fc3c6cca1ab7318b6 | 8 | 0 | 243.9 |
| perf-off-gzip | ab57e8e3aa7a20ae20c8afc5cc3b74a3d437e1bf | 8 | 0 | – |
| perf-off-monocypher | ab57e8e3aa7a20ae20c8afc5cc3b74a3d437e1bf | 8 | 0 | – |
| perf-on-gzip | ab57e8e3aa7a20ae20c8afc5cc3b74a3d437e1bf | 8 | 0 | – |
| perf-on-monocypher | ab57e8e3aa7a20ae20c8afc5cc3b74a3d437e1bf | 8 | 0 | – |
| plain-off-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 88.8 |
| plain-off-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 88.8 |
| plain-off-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 88.5 |
| plain-off-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 200.4 |
| plain-off-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 200.9 |
| plain-off-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 200.6 |
| plain-on-gzip-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 104.9 |
| plain-on-gzip-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 104.9 |
| plain-on-gzip-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 103.7 |
| plain-on-monocypher-1 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 244.0 |
| plain-on-monocypher-2 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 245.8 |
| plain-on-monocypher-3 | 0f19534e56ac9a61cfcdcd9d0e110446a43510da + measure.patch 2e6700cd642645faaeaccb7f0e57dfb8cfa1d922 | 8 | 0 | 243.9 |
