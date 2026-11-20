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
events and the input of each invocation, after the binding of the
arguments and before the preconditions: `Cvalue_callbacks.results.input`
for a body, the state passed to the hook for a hit. The run checks that
the inputs recorded on each stack equal the public request at the start of
the function on that stack (`start-of-call`). The event's producer ID
supplies the slices for the already chosen cache entry. The prototype does
one Inout-based projection per producer and queries it with the frame of
the current invocation.

The producer of a body also records the entry that survives its
preconditions, the state that Eva passes to the hook with the results
(top when no entry survives, recorded as bottom). The points of the body
derive from it, so it is the frame of an analyzed body. A hit does not
reduce its input by its own preconditions, and the precondition of the
producer can read bases that memexec does not compare: the frame of a hit
is its input, which contains its surviving entries. The whole-base result
takes a base reduced by the producer's preconditions from the hit's input.

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

The reconstructions of a hit inherit the admission of memexec, which does
not compare the bases that only a precondition reads. In
`relational-precondition.c`, the body of `f` reads `x`, and its
precondition `x >= g` also reads `g`. The second call, with `g = 4`,
reuses the first, with `g = 9`. Even on the legacy path, the value after
the call then omits fresh values: `r2 ∈ [10..2147483647]` with memexec and
`[5..2147483647]` without. Replay:

```sh
for m in -eva-memexec -eva-no-memexec; do
  dune exec -- frama-c -no-autoload-plugins -load-module eva,inout -eva \
    -eva-domains cvalue -eva-no-hit-log -eva-msg-key progress $m \
    plugins/inout/prototype-state-query/relational-precondition.c \
    > "relational$m.log" 2>&1
  grep -e Reusing -e "r2 ∈" "relational$m.log"
done
```

The prototype classifies every reconstruction of that hit, bitwise, split
and lookback included, as `OMITS_FRESH` before and after `P`:

```sh
dune exec -- frama-c -no-autoload-plugins -load-module eva,inout \
  -eva-domains cvalue -eva-slevel 30 -inout-state-query-prototype fresh \
  plugins/inout/prototype-state-query/relational-precondition.c \
  -then -inout-state-query-prototype hit > relational-prototype.log 2>&1
sed -n '/query hit main\/f@28 before/,/query hit joined/p' \
  relational-prototype.log | grep -E 'query hit main|_FRESH$|EXACT$'
```

`precondition.c` avoids this case: its precondition reads and reduces only
bases that the body does not read.

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

A fixture with a block labelled `E` also runs the selection battery. The
block is never executed; the driver evaluates the expressions of its
statements before `P` under eleven selections: unfiltered, each stack
alone, a selector naming every stack, a predicate keeping every stack, a
selector of two stacks, a predicate dropping one, and the empty selections
(a selector naming a stack that does not reach `P`, a stack rejected by a
predicate, a predicate rejecting every stack). Under each, it records the
stacks in the order of the answer, `is_empty`, the subrequests of
`by_callstack`, the model, `print_states`, and for each expression
`eval_exp` (value, alarms, singleton), `expr_deps` and
`expr_dependencies`; for an lvalue also `eval_lval` (value with its
initialization flag, `is_initialized`, alarms), `eval_address` (location,
zone, alarms), `lval_deps` and `address_deps`; for a call, `eval_callee`.
It then runs the same evaluations on a supplied Cvalue state, alone and
under a selection, which must read neither the store nor the resolver,
`Results.callee P`, the requests of the disabled equality and taint
domains, and the order of the stacks at the initial state and at the start
and the end of each function. The address of a variable without index
reads no state, so its `address_deps` reads neither store either.
`selection.c` is that fixture: on each stack that reaches `P`, `x == y`
and `u == w` hold, so evaluating each stack and evaluating the joined
state give different answers, and its loop calls `g` twice from one site,
on one stack.

## Hit log and resolver

During the analysis, `Eva.Hit_log` records the initialized globals and each
invocation: its callstack, its input after the binding of the arguments to
the formals, and how it was interpreted. The analysis of a body also
records its producer, under the id that the collection hooks receive: the
entries that survive the preconditions, possibly none, and the normalized
states before and after each statement, the same states as the hooks get.
A memexec hit records the producer of the entry it uses. Recording does not
depend on memexec.

After the analysis, a request at the initial state, the start of a
function or before or after a statement goes to the resolver before the
legacy store. On one supplied stack, the resolver rebuilds the state of
each visit on the stack from its own producer, joins the visits in the
order of the analysis, and answers bottom when no visit reaches the point
and top when the results of the function are not recorded. It reads
neither the analysis status nor the stored states. For a fresh
invocation, the rebuilt state is the state the body produced, so it equals
the stored one.

A request on several stacks, a predicate, an enumeration or an unfiltered
request asks the resolver for the state of every stack that reaches the
point, each rebuilt as above. `Eva.Results` keeps its own aggregation on
top: an unfiltered request evaluates the join of the stacks, which the
resolver computes as the legacy consolidation does; a selection evaluates
each selected stack, then joins the answers, even when it names every
stack. The stacks come in the order in which the legacy store enumerates
them: the resolver fills a `Callstack.Hashtbl.create 7` in the order of
their first registration in the store (the call, for the start of a
function; the completion of a body that reaches the point, for a
statement) and reads it back. This order is the hash order, not the order
of the calls. `Eva.Results.is_reachable` goes through the unfiltered
state and is resolved too, including during Eva's post-analysis. On the
legacy path, the marking of unreachable statements in the post-analysis
consolidated, as a side effect, the states before the statements of every
analyzed function. The final-value printer reads these states from the
store. The engine's consolidation skipped the functions whose analysis is
partial, such as a recursive function whose innermost call uses its
specification; it now consolidates the states before their statements.

The resolver declines, and the request reads the legacy store, when the
records are not exact: another domain than Cvalue, `-eva-no-results` or
`-eva-no-results-domain`, a multithread analysis, an analysis that did not
complete, `-eva-no-hit-log`, or results cleared or loaded from a file. It
also declines the points of a memexec hit and every stack below one, whose
states it cannot rebuild yet; it answers the start of a hit from the input
recorded at the call. Once the records contain a hit, it declines every
request on several stacks or none, since the stacks below the hit are not
recorded.

InOut's callwise collection runs in the collection hook, during the
analysis. The `Pre` state of its logic inputs is the start of the function
on the stack, as a request on Eva's results answers it then: top, since no
result is available yet. On the legacy path (`-eva-no-hit-log`), and
whenever the hit log does not record, InOut makes this request, which reads
the store. When the hit log records, it takes top without the request.
Neither state that the hook passes, the input of the call or the entry that
survives its preconditions, becomes the `Pre` state: only the prototype
collection of `-inout-state-query-prototype` reads them (see the first
section). In `pre-label.c`, the input has `p ∈ {&a; &b}` and the surviving
entry `p = &a`. The logic inputs of `\at(*p, Pre)` are `ANYTHING` on both
paths, where the input would give `a; b; p` and the surviving entry
`a; p`. Memexec admission is therefore the same on both paths: a call
whose logic inputs are `ANYTHING` is not cached, and the two identical
calls to `f` analyze the body twice.

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
| `trap:request` | `Eva.Results.get_cvalue_model` on `before P`, the known request, on the legacy path (`-eva-no-hit-log`): the resolver serves it otherwise. |
| `trap:analysis` | `Eva.Engine.register_state`, which reads the recorded state to join it. |
| `trap:collection` | `Eva.Summary.compute_fun_stats`, Eva's statistics hook. |
| `trap:post-analysis` | `Eva.Eval_annots.mark_unreachable`, through its availability read for the postconditions of `f`; its `Eva.Results.is_reachable` requests are resolved. |
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
- `native-equality`: in each native run, all models, values, locations,
  zones, dependencies, callees, alarms and stack lists are natively equal,
  every other answer is equal as text, the reference resolves nothing, and
  every request of the candidate expected on the resolver is resolved.
- `resolver-perturbation`: with `-inout-state-query-acceptance
  wrong-producer`, the resolver rebuilds each visit from the first producer
  of its function. The second call to `f` in `legacy-reads.c` then gets
  `g = 4`: the comparison must report `MISMATCH`, on resolved requests only.
- `selection-order`: on the reference's own answers, `selection.c`
  evaluates `u == w` to `{0; 1}` unfiltered and to `{1}` under a selector
  or a predicate naming every stack, `x == y` to `{0; 1}` on the loop
  stack, whose two visits are joined before the evaluation, and `{1}` on a
  stack with one visit; the divisor, the callee and the supplied state
  differ likewise. Its stacks come in an order that is not the order of
  their names. The candidate serves each of these requests like the
  reference, from the resolver.
- `selection-perturbation`: with `wrong-producer` on `selection.c`, the
  requests on several stacks or none report `MISMATCH`, on resolved
  requests only.
- `inout-collection`: the candidates make no collection read through
  `Eva.Results` from InOut, which takes the `Pre` state without the
  request, while the same driver on the legacy path (`-eva-no-hit-log`)
  makes it.
- `inout-memexec-parity`: with `-eva-memexec`, the legacy path and the hit
  log give the same answers, InOut's included, and Eva's progress messages
  report the same analyses of `f`. In `pre-label.c`, the logic inputs are
  `ANYTHING` and both calls analyze the body. In `precondition.c`, the
  logic inputs are empty and the second call is reused.
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
- unavailable results distinguished from unreachable points (#77), and
  the points of memexec hits, with the requests on several stacks or none
  that the resolver declines once the records contain a hit (#81);
- `Engine.callstacks`, which no reader calls, still enumerates the store.

No fixture reaches the `Domain_store.is_computed` notification, nor the
labels `Eva.Interferences.add_last_analysis`,
`Eva.Eval_annots.mark_green_and_red` and the `Eva.Results` readers that the
requests do not call: `is_reachable_kinstr` and `is_reachable_pos`. The guard records the reads
of these readers, but their attribution has not run. Later tickets extend
the driver.
