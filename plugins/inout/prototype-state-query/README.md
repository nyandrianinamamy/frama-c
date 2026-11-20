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

For each fixture, three processes run the same public requests, built
around the statement labelled `P`:

- The reference runs `-inout-state-query-acceptance reference`. The driver
  disables memexec and the hit log (`-eva-no-hit-log`), so the reference is
  fresh-only and every request reads the legacy store. The guard is off.
- The candidate runs `-inout-state-query-acceptance candidate` with the
  options in `CANDIDATE_OPTIONS` (default `-eva-no-memexec`). The guard
  records every legacy read and every answer of the resolver.
- The native run, `-inout-state-query-acceptance native`, runs the
  reference and then the candidate in one process, on the same AST, and
  compares their models and values with Cvalue's native equality. It also
  records the reads of the reference, which resolves nothing.

Each process writes JSON lines (`-inout-state-query-acceptance-output`): a
header with the command line, loaded plugins, Eva configuration and inputs;
the reads made during the execution, grouped by phase and reader; the
collection reads, by reader and calling frame; and one record per request
with the path expected to serve it, its answer, the reads it made and the
resolutions that served it. `compare.py`
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

Across processes, answers are compared as printed text, so equality is
exact for printed answers; the native run checks the equality of the models
themselves. The script fails on `MISMATCH`, `MISSING` or a failed control.
With `--require-zero-reads` it also fails unless the zero-read gate passes:
no request is `LEGACY` or `UNOBSERVED`, and the candidate made no legacy
read during the execution either. Until a reader is migrated, every request
on stored results is `LEGACY` and the gate fails.

The requests cover stack enumeration (`callstacks`, `by_callstack`),
availability (`are_available`, `Eva.Analysis.status`, `is_reachable`),
models before and after `P`, joined and per stack, the values of the
globals, the entry and initial states, the snapshot export
`Eva.Eva_results.get_results`, and on each supplied stack: the position
adapters at `P` (`before_pos`, `after_pos`), the root call, the initial
state, and for each function its start, its first statement and its end.
They also cover the callwise inputs and outputs that InOut collects for
each call. A request on a supplied Cvalue state must read nothing.

## Hit log and resolver

During the analysis, `Eva.Hit_log` records the initialized globals and each
invocation: its callstack, its input after the binding of the arguments to
the formals, and how it was interpreted. The analysis of a body also
records its producer, under the id that the collection hooks receive: the
entries that survive the preconditions, possibly none, and the normalized
states before and after each statement, the same states as the hooks get.
A memexec hit records the producer of the entry it uses. Recording does not
depend on memexec.

After the analysis, a request on one supplied stack, at the initial state,
the start of a function or before or after a statement, goes to the
resolver before the legacy store. The resolver rebuilds the state of each
visit on the stack from its own producer, joins the visits in the order of
the analysis, and answers bottom when no visit reaches the point and top
when the results of the function are not recorded. It reads neither the
analysis status nor the stored states. For a fresh invocation, the rebuilt
state is the state the body produced, so it equals the stored one.

The resolver declines, and the request reads the legacy store, when the
records are not exact: another domain than Cvalue, `-eva-no-results` or
`-eva-no-results-domain`, a multithread analysis, an analysis that did not
complete, `-eva-no-hit-log`, or results cleared or loaded from a file. It
also declines the points of a memexec hit and every stack below one, whose
states it cannot rebuild yet; it answers the start of a hit from the input
recorded at the call. Unfiltered requests, several stacks and enumerations
still read the legacy store.

InOut's callwise collection takes the input of the invocation from the
hook, in `Cvalue_callbacks.results.input`, instead of reading the start of
the function on the stack from the legacy store. With `-eva-no-hit-log`, it
reads the store as before. That read happens during the analysis, when no
result is available yet, so the legacy path gets top. For an assertion that
reads `\at(*p, Pre)`, the legacy path then reports the logic inputs as
`ANYTHING`, and the hit log as `a; p` (fixture `pre-label.c`). This
difference is expected and reported by its own control; it does not hold
for the other fixtures. It also changes memexec: a call whose logic inputs
are `ANYTHING` is not cached, so with `-eva-memexec` and two identical calls
to such a function, the legacy path analyzes the body twice and the hit log
reuses the first call.

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

The report adds these controls:

- `comparator-mismatch`: altering one candidate answer that agrees with the
  reference adds exactly one `MISMATCH`.
- `guard-sensitivity`: the guard sees reads on every request still expected
  on the legacy store, and neither reads nor resolutions on the requests
  that read neither store (the supplied state and InOut's answers).
- `read-accounting`: each process ends with an `accounting` record. The
  candidate's logged reads equal its execution reads plus the reads of its
  requests, and the reference logs none.
- `reference-independence`: every reference ran without memexec, without
  the hit log, and with the guard off.
- `resolver-path`: every request on a supplied stack is resolved with no
  legacy read, and no other request is resolved.
- `native-equality`: in each native run, all models and values are equal,
  the reference resolves nothing, and every supplied-stack request of the
  candidate is resolved.
- `resolver-perturbation`: with `-inout-state-query-acceptance
  wrong-producer`, the resolver rebuilds each visit from the first producer
  of its function. The second call to `f` in `legacy-reads.c` then gets
  `g = 4`: the comparison must report `MISMATCH`, on resolved requests only.
- `inout-collection`: the candidates make no collection read through
  `Eva.Results` from InOut, while the same driver on the legacy path
  (`-eva-no-hit-log`) does.
- `pre-label-difference`: on `pre-label.c`, only InOut's answer differs,
  with the logic inputs `ANYTHING` on the reference and `a; p` on the
  candidate.
- `zero-read-gate-exit`: `acceptance.sh` first runs `compare.py
  --require-zero-reads --no-write` and records its exit status in
  `zero-read-gate.status`; the status is 1 while the gate fails and 0 once
  it passes.

The comparator and gate controls compare with the differences the evidence
already has, so they also hold for a candidate that differs from the
reference. With `CANDIDATE_OPTIONS=-eva-memexec`, the second call to `f` in
`legacy-reads.c` is a memexec hit: the candidate has no state for the stack
`main/f@27`, the resolver declines the points of the hit, so the stack and
model requests are `MISMATCH` or `MISSING`, `resolver-path` fails and the
script exits 1.

The cram tests `plugins/eva/tests/utils/legacy-read-guard.t` and
`plugins/eva/tests/utils/hit-log-resolver.t` check the guard, the resolver
and the driver output.

Not covered yet:

- `Eva.Analysis.is_computed`, which reads the computation state alone.
  Other plug-ins call it before reading Eva results, among them the InOut
  and Eva server requests, Callgraph, From, Metrics, PDG and Slicing;
- Callgraph relations (`Results.callers`, `callsites`, `is_called` outside
  point queries);
- branch outcomes (`condition_truth_value`);
- alarms and property statuses;
- InOut's functionwise answers and the Server answers; the driver covers
  InOut's callwise answers only;
- restoring a snapshot;
- requests on several stacks, filters and enumeration through the resolver
  (#76), unavailable results distinguished from unreachable points (#77),
  and the points of memexec hits (#81).

No fixture reaches the `Domain_store.is_computed` notification, nor the
labels `Eva.Interferences.add_last_analysis`,
`Eva.Eval_annots.mark_green_and_red` and the `Eva.Results` readers that the
requests do not call: dependencies, taint, `eval_exp`, `eval_address`,
`eval_callee`, `callee`, `equality_class`, `is_empty`, `print_states`,
`is_reachable_kinstr` and `is_reachable_pos`. The guard records the reads
of these readers, but their attribution has not run. Later tickets extend
the driver.
