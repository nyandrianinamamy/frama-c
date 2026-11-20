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

A request on one supplied stack, at the initial state, the start of a
function or before or after a statement, goes to the resolver before the
legacy store. The resolver classifies the point on the stack
(`Hit_log.classify`): it rebuilds the state of each visit from its own
producer and joins the visits in the order of the analysis. It reads
neither the analysis status nor the stored states. For a fresh invocation,
the rebuilt state is the state the body produced, so it equals the stored
one. The public answer converts the classification:

| Classification | When | Public answer |
| --- | --- | --- |
| `Reached s` | A visit reaches the point. | `s` |
| `Unreachable` | Every visit analyzed its body to completion, with its points recorded, and none reaches the point, in a completed analysis; or no invocation of the function is on the stack. | Bottom |
| `Not_analyzed` | The visits interpret the function by its specification or a builtin. | Bottom, as `Eva.Analysis.status` declares |
| `Unavailable Pending` | The analysis is running. | Top |
| `Unavailable Interrupted` | The analysis stopped, and what it computed does not reach the point. | Top |
| `Unavailable Not_recorded` | `-eva-no-results`, `-eva-no-results-domain cvalue` or `-eva-no-results-function`. | Top |

A missing state alone does not make a point unreachable. With
`-eva-no-results` or `-eva-no-results-domain cvalue`, the hit log records
the invocations and how they were interpreted, without their states.

A request on several stacks, a predicate, an enumeration or an unfiltered
request asks the resolver for the state of every stack that reaches the
point, each classified as above. `Eva.Results` keeps its own aggregation on
top: an unfiltered request evaluates the join of the stacks, which the
resolver computes as the legacy consolidation does; a selection evaluates
each selected stack, then joins the answers, even when it names every
stack. The stacks come in the order in which the legacy store enumerates
them: the resolver fills a `Callstack.Hashtbl.create 7` in the order of
their first registration in the store (the call, for the start of a
function; the completion of a body that reaches the point, for a
statement) and reads it back. This order is the hash order, not the order
of the calls. The enumeration and the state are separate
(`Hit_log.select`): a selected stack is enumerated as soon as one of its
visits reaches the point, and the state of the selection is unknown as
soon as one selected stack may contribute an unavailable state. See
"Enumeration and selections" below. `Eva.Results.is_reachable` and
`is_empty` use the reachability of the hit log (see below), including
during Eva's post-analysis.

The final-value printer, the `\init` label of logic evaluation and the
snapshot export (`Eva.Eva_results.get_results`) read the hit log first.
The printer makes the unfiltered request before the first and the return
statements of each function, the `\init` label takes the initialized globals that the
hit log records, and the export takes the state of each recorded stack at
each point. Each reads the legacy store only when the resolver declines.
The export still copies the callers and the analysis status of each
function from the store. A snapshot also saves the records of the hit
log, and restoring it with `Eva.Eva_results.set_results` makes them
current again, so that the requests on the restored results keep their
answers.

The engine's consolidation of the stored states, with
`-eva-join-results`, runs only when the hit log does not describe the
results. It skips the functions whose analysis is partial, such as a
recursive function whose innermost call uses its specification. A request
that reads the legacy store consolidates the states it needs on demand.

The resolver declines, and the request reads the legacy store, when the
records do not describe the current results: another domain than Cvalue, a
multithread analysis, `-eva-no-hit-log`, or results cleared or loaded from
a file, unless a snapshot restores them with its records. It also declines the points of a memexec hit and every stack below
one, whose states it cannot rebuild yet; it answers the start of a hit from
the input recorded at the call. Once the records contain a hit, it declines
the requests on several stacks or none, since the stacks below the hit are
not recorded; after an interrupted analysis, it declines them only at a
point that a recorded stack reaches, and answers Top at the others.

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
| `trap:collection` | `Eva.Summary.compute_fun_stats`, through its `Eva.Results.is_reachable` requests, on the legacy path (`-eva-no-hit-log`): the hit log serves them and the `\init` label of a logic evaluation otherwise, and the run completes. |
| `trap:post-analysis` | `Eva.Eval_annots.mark_unreachable`, through the availability read of its first `Eva.Results.is_reachable` request, on the legacy path (`-eva-no-hit-log`): the hit log serves the marking of unreachable properties and of postconditions otherwise. |
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
- `resolver-path`: every request expected on the resolver is resolved
  with no legacy read, and no other request is resolved.
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

## Reachability and unavailable results

`Hit_log.reach` tells whether a point is reached on some selected stack,
from the classification of each stack: `Reaching` when one stack reaches
it, `Not_reaching` when every selected stack is `Unreachable` or
`Not_analyzed`, and `Unknown` when a stack is unavailable and none reaches
the point. Without supplied stacks, it selects the stacks of the function
in the records, and declines when a negative answer could depend on a
memexec hit. After an interrupted analysis, a point that no recorded stack
reaches is `Unknown` when the request does not name its stacks, as with a
predicate alone, even if each recorded stack is classified, or when a hit
could hide one: the rest of the analysis could reach it. A request that
names its stacks and keeps none of them, by an empty selector or by
predicates that reject each named stack, is `Not_reaching`, whatever the
completion of the analysis and the state of the rejected stacks: no other
stack can contribute. `Eva.Results.is_reachable`,
`is_reachable_pos`, `is_reachable_kinstr`, and `is_empty` on a point
request, use it with the stacks and filters of the request, and read the
legacy store only when it declines. An unknown point is reachable and not
empty, as a point whose legacy state is Top is reachable. These readers
then make no legacy read: Eva's statistics and its marking of unreachable
annotations no longer read the store.

The legacy conversions and the candidate's answers:

| Case | Legacy store | Candidate |
| --- | --- | --- |
| Reached point | The state. | The same state, from the hit log. |
| Unreachable point of a completed analysis | Bottom; `is_empty` true. | The same. |
| Body interpreted by a specification or a builtin, in a completed analysis or on its stack | Bottom at its statements, as `Eva.Analysis.status` declares. | The same; the classification is `Not_analyzed`. |
| Interrupted analysis, body interpreted by a specification or a builtin, request that does not name its stacks | Bottom; `is_reachable` false; `is_empty` true. | Top; `is_reachable` true; `is_empty` false. |
| Nontermination: after a call that does not return | Bottom. | The same. |
| Pending results, during the analysis | Top on a stack; `is_empty` true. | Top; `is_empty` false. |
| Interrupted analysis, point not reached by what it computed | Bottom; `is_reachable` false; `is_empty` true. | Top; `is_reachable` true; `is_empty` false. |
| Interrupted analysis, function never entered, with or without memexec | Bottom; `is_reachable` false; `is_empty` true. | Top without stack; `is_reachable` true; `is_empty` false. |
| Interrupted analysis, model without stack at a point reached on some stacks only | The join of the stacks that reached it. | Top; the stacks that reached it are enumerated. |
| Interrupted analysis, selection of stacks whose states are all known | The join of the selected stacks. | The same. |
| Interrupted analysis, stack with a visit that reached the point and an interrupted one | The state of the first visit. | Top; the stack is enumerated. |
| Results not recorded | Top on a stack; `is_empty` true. | Top; `is_empty` false. |
| Request that names its stacks and keeps none: an empty selector, or predicates that reject each named stack | Bottom, but Top where the states are pending or not recorded; `is_empty` true. | Bottom; `is_empty` true; no stack. |
| Known top model | The top model on a stack. | The same. |
| Equality or taint request on a disabled domain | The declared error, with no read. | The same. |

The differences are deliberate corrections of an ambiguous legacy
conversion: the legacy store answers from a missing row, and cannot tell a
point that no stack reaches from a point whose results are missing. They
hold where the hit log describes the results: the Cvalue domain alone, no
multithread analysis, `-eva-hit-log`, and results neither cleared nor
loaded from a file. Elsewhere every request reads the legacy store, and
`is_empty` answers true from a missing row.

Not corrected:

- `Eva.Analysis.status` answers `analyzed complete` after an interrupted
  analysis, although its interface says partial: Eva counts an aborted
  analysis as computed.
- With `-eva-no-results-domain cvalue`, `Eva.Analysis.status` answers
  `analyzed complete` and `Eva.Results.are_available` true, while no state
  is available.
- With a memexec hit, the requests on several stacks or none read the
  legacy store at a point that a recorded stack reaches, also after an
  interruption (#81).
- Without stack, a request converts Top to a top model, so an unavailable
  result and a known top model print the same.
- A request on a supplied state has no stack: `is_empty` is true, as on the
  legacy path.

The reach modes of the driver, `reach-reference`, `reach-candidate` and
`reach-native`, make these requests on every labelled statement and every
function of the input files, on each stack that the call hooks of Eva see.
The fixtures use three conventions: a call to `stop_analysis` aborts the
analysis through `Eva.Analysis.abort`; a call to `pending_probe` makes
requests during the analysis; a global `top_initial_state` starts the
analysis from a top state. An `internal` line prints the classification
before its public conversion. The cram test
`plugins/eva/tests/utils/reach-availability.t` runs them on a completed
analysis with a specification, a builtin and a nonterminating call, an
interrupted analysis, with and without memexec, the three options that
disable results, pending results, a recursion, a known top model and
disabled domains.

### Enumeration and selections

A request on several stacks, a predicate, an enumeration or an unfiltered
request is answered by `Hit_log.select` on the selected stacks: those that
the request names, by default the stacks of the function in the records,
that satisfy its predicates. The answer separates two things:

- the enumeration (`callstacks`, `by_callstack`): each selected stack with
  a visit that reaches the point, in the order of the legacy store. One
  visit that reaches the point is positive evidence, whatever the other
  visits on the stack, and whatever the state of the other stacks;
- the state: known when the records give the state of each selected stack
  that may reach the point, unknown otherwise.

The public conversions:

| Selection | Enumeration | Model |
| --- | --- | --- |
| The request names its stacks and keeps none: an empty selector, or predicates that reject each named stack | None. | Bottom, whatever the completion of the analysis, a memexec hit, and the state of the rejected stacks: known, unavailable, not analyzed or not recorded. |
| Every selected stack is classified, and its state known or unreachable | The stacks that reach the point. | Their join, or each stack evaluated then joined, as on the legacy path; Bottom if none reaches it. |
| A selected stack is unavailable: its state, or the state of one of its visits | The stacks that reach the point, including that one if a visit reached it. | Top: a top model without selection, the error Top with one. |
| Pending results, or states not recorded at the point | None, as on the legacy path. | Top. |
| After an interruption, no selected stack reaches the point | None. | Top, unless the request names its stacks and each one it keeps is classified: Bottom then. |
| A memexec hit in the records | The legacy store (#81), except after an interruption when no selected stack reaches the point: Top then. | The same. |

The first row applies before the others. The legacy store answers Bottom
for such a request, but Top where the states are pending or not recorded;
its `is_empty` answers true.

A selector that names one stack, which its predicates keep, makes the
request on that stack: Top when its state is unavailable, as on the legacy
path. Its enumeration lists the stack if a visit reached the point. The
subrequests of `by_callstack` are such requests, one per enumerated stack.

After an interruption, the state of a stack that reaches the point is the
one that the analysis computed, as for a request on that stack alone, and
the stacks that the analysis did not enter are not part of a selection
that a recorded stack reaches. A later visit, or a stack that the analysis
would have entered later, could add values to these answers. The legacy
store makes the same assumption.

`reach-availability.t` checks each case with `interrupted.i` (R reached by
the first call, unavailable on the second; L reached by none),
`interrupted-three.i` (two stacks known at R, one unavailable),
`interrupted-loop.i` (one stack whose first visit reaches R and second
visit is interrupted), `interrupted-spec.i` (bodies interpreted by a
specification and a builtin before the interruption), the pending, not
recorded, known top, recursion and memexec fixtures. The selections are
the unfiltered request, every stack by a selector and by a predicate,
each stack alone by a predicate, every stack but one by a selector and by
a predicate, each stack by a selector with a predicate that rejects it,
every stack by a selector with a predicate that drops one or rejects
each one, every stack but one by a selector with a predicate that keeps
only that one, and none, by an empty selector and by a predicate. Each
selection is compared with the reference, in text and natively, and must
be served by the hit log without legacy read, except with a memexec hit.
Its model is Bottom exactly when `is_empty` answers true. The test counts
the answers of the selections that name their stacks and keep none, in
every fixture: no stack, no subrequest, Bottom, `is_empty` true, without
legacy read; and lists the fixtures where the reference answers Top for
them: pending and not recorded results.

## Plug-in readers and semantic facts

The `plugins-` modes run the battery of the plug-ins that read Eva's
results, on `plugins.c`; `plugins/eva/tests/utils/plugin-readers.t` runs it
on a copy, `plugins.i`, and shows each answer. Only Eva and InOut are
loaded, with autoload disabled; Callgraph and Server come with their
dependencies, and the header records the plug-in list and whether the
optional Eva server API is loaded, which it is not. The battery asks:

- `Eva.Analysis.is_computed`, which Server's filters and Callgraph ask
  before reading Eva's results;
- the call relations: `Eva.Results.is_called`, `callers` and `callsites`
  of each function;
- the guard outcomes: `Eva.Results.condition_truth_value` on each
  conditional;
- Callgraph: the graph, recomputed from Eva's results, and its order;
- InOut: `kf_inputs`, `kf_external_inputs`, `kf_outputs`,
  `kf_external_outputs` and `get_precise_inout` of each function, callees
  first; `get_precise_inout ~stmt` of each call that the analysis made;
  `stmt_inputs` and `stmt_outputs` of each instruction; `expr_inputs` of
  each assigned or returned expression that reads memory;
- Server: the read and written filters that InOut registers, on each
  global variable (`kernel.ast.fetchGlobals`), and Ivette's array of
  properties, with the alarms (`kernel.properties.fetchStatus`);
- the status that Eva emits on each property, and the consolidated status;
- the statistics that Eva computes from its results: the number of alarms
  and the coverage of statements and functions. The statistics of the
  execution (memory, time, iterations, memexec hits and misses, widenings,
  unrolling, partitioning index) are written apart, in an
  `execution-statistics` record, and are not compared.

Eva's final display computes the graph of Callgraph and InOut's outputs of
the analyzed functions; the driver clears these memos, so that each
request computes its own answer from Eva's results. InOut's callwise
results, which it records during the analysis, are kept: those requests
read nothing. The modes are `plugins-reference`, `plugins-candidate`,
`plugins-native`, `plugins-wrong-producer` and `plugins-trap`. The last
arms the guard's `Trap_except` mode: every legacy read, in any phase,
whose innermost reader is not exempt aborts Eva. The only exempt reader is
`Eva.Engine.register_state`, which joins each new state with the recorded
one during the analysis.

The hit log records the facts that these readers need beyond the states.
Each answer equals the legacy one; where the records cannot give it, the
reader declines to the legacy store.

| Fact | Readers | Recorded as | Equal to the legacy answer because | Declines | With memexec hits (#81) |
| --- | --- | --- | --- | --- | --- |
| Completion | `Eva.Analysis.is_computed` | The completion of the records. | The records are sealed or interrupted when the computation state changes. | When the records do not describe the results. | Unaffected. |
| Call relations | `is_called`, `callers`, `callsites`, `nb_callsites`; Callgraph; InOut's external effects; the snapshot export | The callstack of each invocation. | The legacy table registers a call when Eva chooses how to interpret it, after the invocation is recorded and before any hook. | Once the records contain a hit. | Needs the calls below a hit. |
| Guard outcomes | `condition_truth_value` | The fireable branches of each conditional, with each analyzed body, whatever the results recorded. | The legacy table joins the same transitions of every analysis of the body. | While the analysis runs; once the records contain a hit. | Needs the outcomes of the reused producer. |
| Analyzed function | The marking of postconditions | The kind of each invocation. | A function is `Analyzed` when one of its calls analyzed its body or reused it. | Before the analysis completes; on an unresolved invocation. | Unaffected. |
| Analysis status and callers | `Eva.Eva_results.get_results` | The kind of each invocation, and whether Eva saves the results of each analyzed body. | The status table registers the same target for each call, and the records merge the statuses in the order of the calls with the table's own merge. | Before the analysis ends; once the records contain a hit; on an unresolved invocation. | Needs the calls below a hit. |

The statuses, the alarms and the statistics are stored apart from Eva's
results: reading them reads neither store. Eva computes them after the
analysis from requests that the hit log answers, and the battery compares
them with the reference. The wrong-producer control changes the guard
outcomes of `g` and `h`, InOut's outputs of both, and the coverage of
Eva's statistics.

`compare.py` adds two controls: `plugins-trap` (the candidate completes the
battery under the trap with the answers of the reference; on the legacy
path, the trap aborts the run at `Eva.Summary.compute_fun_stats`) and
`plugins-perturbation` (the wrong producer changes the guard outcomes and
InOut's effects, and only requests served by the resolver or the reports
that Eva derives from its results).

## Not covered

Not covered yet:

- the points of memexec hits, with the requests on several stacks or none,
  the call relations, the guard outcomes and the snapshot metadata, which
  the hit log declines once the records contain a hit (#81);
- `Eva.Analysis.status` and `Eva.Results.are_available`, which still read
  the analysis status;
- `Engine.callstacks`, which no reader calls, still enumerates the store;
- the optional Eva server API, and the other plug-ins that ask
  `Eva.Analysis.is_computed` before reading Eva's results: From, Metrics,
  PDG and Slicing.

No fixture reaches the `Domain_store.is_computed` notification, nor the
label `Eva.Interferences.add_last_analysis` and the `Eva.Results` readers
that the requests do not call: `is_reachable_kinstr`, and
`is_reachable_pos` outside the reach modes. The guard records the reads of
these readers, but their attribution has not run. Later tickets extend the
driver.
