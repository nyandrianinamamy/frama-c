# Recorded state-query results

The replay passed on Frama-C base
`375ab36aa5b3e254f6bf13860cb7641561a0c8c1` with the local prototype patch.
Run `bash plugins/inout/prototype-state-query/run.sh` to regenerate and validate
the evidence. The command uses the tested OCaml/Dune switch and only the Cvalue
domain with slevel 30. Eva and Inout pull in Callgraph and Server through
their dependencies. Each fixture runs in a separate process. Its fresh and
memexec-enabled analyses share the AST, with Eva state cleared between runs.
The `precondition.c` row and the `start-of-call` check were added later and
replayed with the other rows on the revision that adds them. On every row,
the inputs recorded on each stack equal the public request at the start of
`f` on that stack.

Each analyzed fixture had two fresh body observations. The tested memexec
phase then reported `Body/4` followed by `Reuse/4`, except for the
read-before-write fixture, which reported `Body/4` and `Body/5`, and the
precondition fixture, which has three calls and reported `Body/5`,
`Reuse/5` and `Body/6`.
Here, A and B refer to the first and second invocations. The loop fixture
uses the same callstack for both. Every comparison covers the whole native
Cvalue model, including saved caller-local and uninitialized bindings.

| Fixture | Expected check | Observed with memexec | Result |
| --- | --- | --- | --- |
| `original.c` | Each stack keeps its own frame. | Before and after P, A has `g=4` and B has `g=9`, with `x=10` and `y=11` on both. The joined result has `g={4,9}`. Legacy has no B contribution. Substituting the raw producer gives the wrong B frame. | PASS |
| `loop.c` | Both visits to a single call site contribute. | The bitwise join has `g={4,9}` and `i={0,1}` at both points. Legacy and raw-producer joins omit the second visit. | PASS |
| `read-before-write.c` | Reading the initial `g` prevents a hit. | The prefix reads `g`, writes local `t`, and then overwrites `g` at P. The two bodies retain `t=4` and `t=9`, with `g=0` after P. | PASS |
| `guard.c` | Preserve the read-only reduction from `x=[0,10]` to `x=[0,4]`. | Bitwise is exact before and after P, for each stack and joined. The write-only control keeps `x=[0,10]` at both points and has `y=[0,4]` after P. Native inclusion confirms it contains fresh strictly. | PASS |
| `unreachable.c` | Unreachable queries stay bottom even on the hit. | The result is bottom before and after P for each stack and joined. Eva reports results available for the function, with zero reachable stacks at P. | PASS |
| `partial-base.c` | Preserve only `s.a` from the prefix and pass through `s.b`. | Before P, B is exactly `(s.a,s.b)=(1,9)` with bitwise reconstruction. The whole-base control contains fresh strictly with `s.a={1,8}` and `s.b={4,9}`. After P the whole base was overwritten and both strategies give `(1,0)`. | PASS |
| `maybe-write.c` and `maybe-write-goto.c` | Preserve the conditional write while using the B input on the untouched edge. | B before P has fresh `g={1,9}`. The joined-payload fallback gives `{1,4,9}` and contains fresh strictly at B. The predecessor split is exact. All candidate reconstructions give exact `g=0` after P. Joining A and B already makes the bitwise fallback exact at both points. | PASS |
| `maybe-write-upstream.c` | The predecessor split can only recover an earlier merge with extra context. | With `h=2` between the conditional and P, bitwise and immediate split both contain fresh strictly at B before P. Looking across the independent assignment recovers exact `g={1,9}` while retaining `h=2`. All three are exact joined and after P. | PASS |
| `precondition.c` | Record each input before the precondition, rebuild an analyzed body from the entry that survives it, and never give a hit the producer's reduction. | The first call records the input `z ∈ [--..--]` and the surviving entry `z ∈ [9..2147483647]`, and its points have the latter. The third records `z ∈ {1}` and no surviving entry, and its points are bottom. Bitwise is exact on every analyzed body. The hit reuses the first call with `g = 4`, where fresh has `z ∈ [4..2147483647]`: whole-base, bitwise, split and lookback give `z ∈ [--..--]` and contain fresh strictly, and the producer's `z ∈ [9..2147483647]` omits part of it. | PASS |
| `original.c` with `-eva-no-results-function f` | Distinguish absent results from unreachable P. | Both body calls occur, with no point payloads. The legacy known-stack API returns `Error Top`. The joined `get_cvalue_model_result` returns `Ok` with a top model. Availability is false and zero stacks are returned at both points. | PASS |

Every ordinary body was independently reconstructed from its frame and the
projected bitwise payload, then checked against the recorded body and the
fresh legacy query. Both the direct and earlier-merge remedies need two
alternative records at the affected before-point per producer. One record
carries a 32-bit written offsetmap and the other carries a pass-through
reference. The earlier-merge case also checks one additional CFG edge.
The ordinary bitwise payload retained four projected entries at two points
for the direct conditional fixture and six for the earlier merge. Both
retained two invocation frames, and one producer sufficed in the reuse run.

These counts describe the prototype representation. Full diagnostic states,
the independently built write-only control, allocator overhead, and time
are outside the storage counts. The equality and inclusion checks establish
the relationships to the observed fresh models for these fixtures.

## Zero legacy reads (#80)

Revision `a6c5427b46029aaa416d3d1b2bd4a57998ee48c0`, clean worktree, one
command:

```sh
bash plugins/inout/prototype-state-query/acceptance.sh <empty-directory>
```

It exited 0 in 140 s. Configuration: `frama-c -no-autoload-plugins
-load-module eva,inout -eva-domains cvalue -eva-slevel 30`, candidate
option `-eva-no-memexec`; Callgraph and Server are loaded through the
dependencies of Eva and InOut. Every reference, candidate and control
runs in its own process.

Each candidate runs under the continuous trap: the guard is armed once,
before the analysis, with the trap of every phase, and is never disarmed.
Any read of the legacy result store, from the initialization through the
analysis, the collection, the post-analysis passes and every request,
aborts Eva. Each candidate completed its battery with the guard armed
once (`trap:all`), no read logged and none trapped.

| Fixtures | Requests | Disposition |
| --- | --- | --- |
| 14 point fixtures (`legacy-reads.c` to `precondition.c`) | 31 to 54 each | all `MATCH` |
| `selection.c` | 478 | all `MATCH` |
| `plugins.c` | 199 | all `MATCH` |
| `statuses.i` (`-eva-no-results-function no_results`) | 100 | all `MATCH` |

Zero-read gate: 0 reads during the executions, 0 requests served by the
legacy store, no failing gate record.

Reads per phase, legacy path (`record` mode, `-eva-no-hit-log`) against
the candidate:

| Battery | Initialization | Analysis | Collection | Post-analysis | Requests |
| --- | --- | --- | --- | --- | --- |
| `legacy-reads.c`, legacy path | 0 | 39 | 19 | 250 | 247 |
| `plugins.c`, legacy path | 0 | 294 | 134 | 1775 | 1440 |
| every candidate | 0 | 0 | 0 | 0 | 0 |

No reader of the store runs during the initialization on either path:
there, the trap has nothing to catch, and `trap:initialization` exits 0.

Positive controls, each in its own process on the legacy path, exit 1 on
the first read of their phase: `trap:analysis` at
`Eva.Engine.register_state`, `trap:collection` at
`Eva.Summary.compute_fun_stats`, `trap:post-analysis` at
`Eva.Eval_annots.mark_unreachable`, `trap:request` at
`Eva.Results.get_cvalue_model`. The candidate command itself, run on the
legacy path, aborts at `Eva.Engine.register_state` on `legacy-reads.c`
and on `plugins.c` (`continuous-trap-legacy-path`). After the battery, a
request on cleared results aborts with no read logged before it
(`tail-probe`). The gate rejects the two legacy-path runs as candidates
(`gate-sensitivity`: 308 and 1178 execution reads).

On the candidate, the three writers resolve from the hit log during the
analysis of `plugins.c`: 206 states, 24 call targets and 12 guard
outcomes. With the hit log declining every request (`store-check`),
the legacy tables written from the records give the reference's answers
on every fixture.

Snapshot round trip on `plugins.c`: the exported statuses and callers,
the statuses before the export, after an intervening analysis (they
differ) and after the restore (equal to those before the export) match
the reference, under the trap. With wrong exported statuses and callers
(`plugins-perturb-calls`), only `export.calls` differs: the restored
records serve the requests. With the hit log declining after the restore
(`plugins-restore-check`), the statuses come from the legacy tables that
the payload wrote: they match, with 19 legacy reads after the restore and
none during the export (`restored-payload`).

Native equality in one process: 151 models and values on `plugins.c`, 69
on `statuses.i`, none differing.

All controls pass: the five phase traps, `comparator-mismatch`,
`continuous-trap`, `continuous-trap-legacy-path`, `tail-probe`,
`guard-sensitivity`, `hit-log-registration`, `legacy-store-writes`,
`read-accounting`, `reference-independence`, `resolver-path`,
`native-equality`, `resolver-perturbation`, `selection-order`,
`selection-perturbation`, `plugins-perturbation`,
`export-payload-perturbation`, `restored-payload`, `snapshot-round-trip`,
`inout-collection`, `inout-memexec-parity`, `gate-sensitivity` and
`zero-read-gate-exit`.

The reachability battery runs in the cram test
`plugins/eva/tests/utils/reach-availability.t`: on each fixture but
`interrupted-hit.i`, whose memexec hit is outside the trapped
configuration, the candidate runs under the same continuous trap, and on
`points.i` and
`interrupted.i` the payload exported from the records restores legacy
tables that give the reference's answers (`reach-restore-check`).
