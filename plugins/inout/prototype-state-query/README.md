# Throwaway Eva state-query prototype

Run `bash plugins/inout/prototype-state-query/run.sh` from this checkout. The
runner activates the main checkout's switch, checks the environment, builds
`@install` with eight jobs and runs each fixture with only Cvalue enabled.
It generates and validates logs, then builds a standalone walkthrough at
`plugins/inout/prototype-state-query/evidence/walkthrough.html`. Pass a path
as the first argument to write the artifacts elsewhere.

The runner uses a fresh Eva analysis with memexec off for the baseline and
clears the Eva state before the memexec-enabled run. The AST stays shared, so
comparison uses the native whole-model equality and inclusion operations on
the same base identities. Each run records the real `Body` and `Reuse`
events and their entry frames. The event's producer ID supplies the slices
for the already chosen cache entry. The prototype does one Inout-based
projection per producer and queries it with the current frame.

The diagnostic whole-base result joins the producer and hit bindings for a
partly written base. The bitwise result preserves sure writes and refinements
of operational inputs, keeps current-frame pass-through, and joins the
producer's may-only bits with the current frame. The write-only control
omits the read footprint. The split and lookback results can replace a
may-only range using a retained write slice or the current input, depending
on the recorded incoming edge.

The lookback traverses one nonbranching assignment of an integer constant
to a nonvolatile global scalar whose local footprint is disjoint from the
affected range. The earlier incoming edges and the observed merged model
must support the same slice split as a direct predecessor. This deliberately
covers only the fixture. Longer or more complex merges may require
preserving provenance as the body runs or reanalyzing it.

The prototype stores the raw body state as a diagnostic control for model
comparisons. Storage counters report frame/point records and projected
entries and count the alternative offsetmaps, pass-through references, and
lookback edges separately. They are logical counts, not memory or runtime
measurements. The experiment exercises finite ordinary C bases, scalar
updates, and field slices. It does not establish a general reconstruction
theorem for Cvalue, other domains, nested hits, scope effects, or imported
results. See [the recorded results](RESULTS.md).

## Acceptance driver and legacy-read guard

Run `bash plugins/inout/prototype-state-query/acceptance.sh [evidence-dir]`
to replay the acceptance driver alone; `run.sh` also runs it, into
`evidence/acceptance`. The configuration is the minimal one: no plugin
autoloading, Eva and InOut loaded explicitly, Callgraph and Server through
their dependencies, only the Cvalue domain, slevel 30.

For each fixture, two processes run the same public requests on the
statement labelled `P`:

- The reference runs `-inout-state-query-acceptance reference`. The driver
  disables memexec, so the reference is fresh-only, and leaves the guard
  off.
- The candidate runs `-inout-state-query-acceptance candidate` with the
  options in `CANDIDATE_OPTIONS` (default `-eva-no-memexec`). The guard
  records every legacy read.

Each process writes JSON lines (`-inout-state-query-acceptance-output`): a
header with the command line, loaded plugins, Eva configuration and inputs;
the reads made during the execution, grouped by phase and reader; and one
record per request with its answer and the reads it made. `compare.py`
compares the two files of each fixture and writes `report.md` and
`report.json` with the revision, a SHA-256 of each input and one
disposition per request:

| Disposition | Meaning |
| --- | --- |
| `MATCH` | Equal answers and no legacy read during the request. |
| `LEGACY` | Equal answers served with legacy reads. |
| `MISMATCH` | Different answers. |
| `MISSING` | The request is absent from one of the runs. |
| `UNOBSERVED` | Equal answers, with the candidate's guard off. |

Answers are compared as printed text, so equality is exact for printed
answers, and native inclusion between models is not checked across
processes. The script fails on `MISMATCH`, `MISSING` or a failed control.
With `--require-zero-reads` it also fails unless the zero-read gate passes:
no request is `LEGACY` or `UNOBSERVED`, and the candidate made no legacy
read during the execution either. Until a reader is migrated, every request
on stored results is `LEGACY` and the gate fails.

The requests cover stack enumeration (`callstacks`, `by_callstack`),
availability (`are_available`, `Eva.Analysis.status`, `is_reachable`),
models before and after `P`, joined and per stack, the values of the
globals, the entry and initial states, and the snapshot export
`Eva.Eva_results.get_results`. A request on a supplied Cvalue state must
read nothing.

The guard (`Eva.Legacy_read_guard`) sees three kinds of reads:

- getters and enumerations of any `Domain_store`, which every alias reaches:
  `Cvalue_results`, the domain-level `Store` modules, the engine's store,
  the snapshot export, the `\init` label of logic evaluation, the
  final-value printer and the consolidation of states;
- the store's own availability flag;
- the availability decision of point queries: the computation state and the
  analysis status of the function in the engine, `Results.are_available`,
  `Eva.Analysis.status`, the consolidation of per-function states, the
  postcondition marking of `Eval_annots` and the snapshot export.

Each read carries the phase (initialization, analysis, collection by
`Cvalue_callbacks` hooks, post-analysis, or request), the outermost
labelled reader, and the first stack frame outside Eva when the read does
not come from Eva's own analysis. The driver arms the guard through its API,
so arming it does not invalidate Eva's results. The controls run in separate
processes with `-inout-state-query-acceptance trap:<phase>`, where the first
read in that phase aborts Eva with exit status 1:

| Control | Expected trap |
| --- | --- |
| `trap:request` | `Eva.Results.get_cvalue_model` on `before P`, the known request. |
| `trap:analysis` | `Eva.Engine.register_state`, which reads the recorded state to join it. |
| `trap:collection` | `Eva.Summary.compute_fun_stats`, Eva's statistics hook. |
| `trap:post-analysis` | `Eva.Eval_annots.mark_unreachable`, through `Eva.Results.is_reachable`. |
| `trap:initialization` | None: the run completes. |

The report adds four controls:

- `comparator-mismatch`: altering one candidate answer that agrees with the
  reference adds exactly one `MISMATCH`.
- `guard-sensitivity`: the guard sees reads on every request on stored
  results that the candidate made, and none on the supplied state.
- `read-accounting`: each process ends with an `accounting` record. The
  candidate's logged reads equal its execution reads plus the reads of its
  requests, and the reference logs none.
- `zero-read-gate-exit`: `acceptance.sh` first runs `compare.py
  --require-zero-reads --no-write` and records its exit status in
  `zero-read-gate.status`; the status is 1 while the gate fails and 0 once
  it passes.

Both controls compare with the differences the evidence already has, so
they also hold for a candidate that differs from the reference. With
`CANDIDATE_OPTIONS=-eva-memexec`, the second call to `f` in `legacy-reads.c`
is a memexec hit: the candidate has no state for the stack `main/f@27`, so
the stack and model requests are `MISMATCH` or `MISSING` and the script
exits 1.

The cram test
`plugins/eva/tests/utils/legacy-read-guard.t` checks the guard and the
driver output.

Not covered yet:

- `Eva.Analysis.is_computed`, which reads the computation state alone.
  Other plug-ins call it before reading Eva results, among them the InOut
  and Eva server requests, Callgraph, From, Metrics, PDG and Slicing;
- Callgraph relations (`Results.callers`, `callsites`, `is_called` outside
  point queries);
- branch outcomes (`condition_truth_value`);
- alarms and property statuses;
- InOut and Server answers;
- restoring a snapshot.

No fixture reaches the `Domain_store.is_computed` notification, nor the
labels `Eva.Interferences.add_last_analysis`,
`Eva.Eval_annots.mark_green_and_red` and the `Eva.Results` readers that the
requests do not call: dependencies, taint, `eval_exp`, `eval_address`,
`eval_callee`, `callee`, `equality_class`, `is_empty`, `print_states`,
`is_reachable_kinstr` and `is_reachable_pos`. The guard records the reads
of these readers, but their attribution has not run. Later tickets extend
the driver.
