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

## Plug-in readers

`acceptance.sh` passed on the revision that adds this section, with the
plug-in fixture `plugins.c`: its 195 requests are `MATCH`, with the
answers of the reference and no legacy read, and the native run finds no
difference. In `plugin-readers.t`, the battery also runs on `statuses.i`,
which has a function of each analysis status; the snapshot of the
statuses, as all the other answers, equals that of the reference. The
request that reads these statuses after the restoration reads them from
the status table with the guard off: its count of legacy reads covers the
export and the restoration only. The callers in the snapshot are not
compared, since the hit log answers the requests on callers on the
restored results. The controls `plugins-trap` and `plugins-perturbation` pass,
with every other control. The zero-read gate fails, as expected: the
registration of the states by the engine and the availability readers
still read the legacy store.
