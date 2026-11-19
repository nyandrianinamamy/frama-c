# Lean model of statement reuse

This directory holds the Lean reference model for the reuse of cache entries in
Eva. It defines a small language, a concrete memory, executions and the
observations that a cache entry makes claims about, and it proves theorems
about them: frame preservation up to recorded lexical sweeps, the match and
product lemmas, sound cache-entry construction, shared Inner coverage
on the matching key, projected and whole-product hits within one analysis, and
the answers of state queries on the callstack of a hit.

The theorems are about the model. They do not verify the OCaml code of Eva.
Whether Eva meets the hypotheses of a theorem is a separate question, answered
claim by claim in the correspondence record,
[`docs/eva/reuse-correspondence/`](../docs/eva/reuse-correspondence/README.md).

The model is written for this effort. Its published basis is the ECOOP 2025
paper *Reusing Caches and Invariants for Efficient and Sound Incremental Static
Analysis* ([LIPIcs, ECOOP 2025, paper 28](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2025.28)).

## Build

From the root of a clean checkout, with [elan](https://github.com/leanprover/elan)
installed:

```sh
cd lean && lake build --wfail
```

elan installs the toolchain pinned in `lean-toolchain` on first use. Run the
command from this directory: elan selects the toolchain from the
`lean-toolchain` file of the current directory, and `lake --dir lean` run from
the repository root would use elan's default toolchain instead.

The build fails when:

- a proof does not check;
- Lean emits a warning (`--wfail`), which includes `declaration uses 'sorry'`;
- a theorem listed in `Checks/Axioms.lean` depends on an axiom other than
  `propext`, `Classical.choice` and `Quot.sound` (`#check_axioms`).

The build output shows the `#print axioms` result of each listed theorem, also
when the modules are already built (Lake replays their messages).

The ordinary Frama-C build does not need Lean: the root `dune` file lists the
directories that Dune reads, and `lean` is not among them.

## Pins

- Toolchain: `leanprover/lean4:v4.28.0`, in `lean-toolchain`.
- Packages: none. The model uses Lean's core library only, and
  `lake-manifest.json` lists no package.
- CI: [`.github/workflows/lean-model.yml`](../.github/workflows/lean-model.yml)
  installs elan 4.2.4 from its release archive, checked against a SHA-256
  digest, and pins `actions/checkout` to a commit. It runs `lake build --wfail`
  on a push or a pull request that changes a file under `lean/` or the workflow
  itself, and on manual dispatch. Other changes do not start it.

## Contents

| File | Content |
|---|---|
| `ReuseModel/Syntax.lean` | Blocks, values, expressions, statements, programs; the fragment conditions `WellFormed` and the `Subject` of the observations; the lemmas that a function body and a statement inside the observed statement are in the fragment |
| `ReuseModel/Memory.lean` | The memory interface `Memory` with its laws; the memory `FunMem`, which meets them |
| `ReuseModel/Semantics.lean` | Events, evaluation, configurations, the step function, executions (`run`) and finite sequences of steps (`Steps`), for any program; finite prefixes (`Prefix`) of a subject |
| `ReuseModel/Observations.lean` | Exit, Reach, Safety and visits, of a subject |
| `ReuseModel/Frame.lean` | `InFrame`, `frame_of_not_written`, `frame_lemma`, and the exact and sufficient conditions for no frame rewrite |
| `ReuseModel/Domain.lean` | Agreement of memories on a set of blocks, `Combinable`; abstract domains (`Domain`) with their laws `FilterSound`, `RelateSound`, `FilterExact`, `ReuseSound` and `Extensional`; closed sets, the product of two domains and the laws it keeps; closure, decomposition and exactness on two sets with the same members; the strong form of `filter` sound and exactness, derived from the decomposition; `match_filtered`, `match_lemma`, `product_lemma`, `projected_match` |
| `ReuseModel/Replay.lean` | Allocation agreement and agreement of matching executions on every finite prefix |
| `ReuseModel/Entry.lean` | Footprints, cache entries, producer soundness, `CacheEntry.sound_of_producer`, and `CacheEntry.shared_inner` |
| `ReuseModel/Hit.lean` | Replay admission, the unchanged exit frame, and the projected and whole-product hit theorems |
| `ReuseModel/SideTables.lean` | The four obligations for side-table accesses in skipped work |
| `ReuseModel/Query.lean` | Query points (statement, callstack, before or after), visits at a point, the hit log, the reconstruction rules (`HitLine.answer`, `query`), the soundness of the inner part (`InnerPartSound`) and of an inner part with states on the key only (`innerPartSound_of_key`), `replay_trace` and `CacheEntry.query_sound` |
| `Checks/AxiomCheck.lean` | The `#check_axioms` command |
| `Checks/Axioms.lean` | `#print axioms` and `#check_axioms` for each theorem |
| `Checks/Examples.lean` | Aliasing, a dangling pointer after a return, and a call that does not return, using `frame_no_sweep_rewrite` for that case; the body of a function as the subject; comparisons with the null pointer |
| `Checks/Domains.lean` | A non-relational domain that meets every law, alone and in a product with itself, and a match it admits; a domain of equalities with an identity `filter`, which fails `relate` sound on the fact `y == z` and the closed key `{x}`; a one-state domain with an identity `filter` that meets every law; a product with an empty concretisation on which `filter` is not exact; a domain that meets the other laws, not `Extensional`, in which `[0]` is closed and `[0, 0]` is not |
| `Checks/Entries.lean` | A load that faults before an overwrite, an assertion before an overwrite, a return with an incomplete footprint, and the need to distinguish allocation state and writes at normal exits |
| `Checks/Sweeps.lean` | A lexical local whose address escapes into a written holder, an untouched block preserved across the sweep, a future pointer that needs a rewrite, a return from a lexical scope, a matching exit whose frame is rewritten, a comparison of a marked holder, and a sweep in a callee's scope |
| `Checks/Inner.lean` | A two-visit loop, the producer premises, a distinct matching memory, and negative cases for the first visit alone and for coverage outside the key, plus a fresh local forced into the lookup key |
| `Checks/Hit.lean` | The value-domain hit instance and checked failures of liveness, allocator agreement and the unchanged frame |
| `Checks/WholeProduct.lean` | A whole-product hit, rejections for differences in either component, and loss of a relation on a projected hit without current-side closure |
| `Checks/SideTables.lean` | Positive and negative cases of the four obligations |
| `Checks/Query.lean` | Two calls of one body in one run with a hit log line each: an untouched block answering 4 and 9, an overwritten block answering 5 before the write and 0 after it, the key block, disabled reconstruction, a local of the body answering top, and the negative checks of the naive answers; two lines on one callstack, where the first line's answer misses the member of the second; the callstack of a point, before and after a statement, the marks of the sweeps in the frame rule, and the end of a statement's execution |
| `Checks/Fragment.lean` | Statements that meet the fragment conditions: one outside the function bodies, a function body, and a statement inside one. Programs and statements that do not: duplicate labels in the observed statement, a label of a body reused outside, duplicate labels across two bodies, direct recursion, mutual recursion |

## What the model contains

- **Language.** Whole-block loads and stores, sequencing, conditionals,
  `while`, lexical scopes, direct calls, return and labelled assertions. Every statement
  carries a label, by which the observations name it. A program is a finite
  list of named function definitions, with the blocks of its globals. The
  integer `0` is the null pointer: `==` between a pointer and `0` gives `0`,
  in either order of the operands, and `==` between a pointer and a nonzero
  integer is ill-formed.
- **Fragment.** `WellFormed p s` states that the statement `s` of the program
  `p` is in the fragment of the model:
  - `namesUnique`: each function is defined once;
  - `nonRecursive`: some rank on function names decreases along every direct
    call;
  - `labelsUnique`: the labels of the function bodies of `p` are pairwise
    distinct, so that a label names one statement of the program text;
  - `stmtLabels`: `s` is a statement of a function body of `p` (the body
    itself or a statement inside it), or else the labels of `s` are pairwise
    distinct and distinct from those of the function bodies.

  The observed statement can thus be the body of a function, a statement
  inside a body, or code outside the functions that calls into them, as in
  most examples. In each case a label names one statement of `s` and of the
  function bodies. `WellFormed.body` and `WellFormed.sub` show that the body of
  a function that a call reaches, and a statement inside the observed
  statement, are in the fragment with the same program.

  A `Subject` bundles a program, the observed statement and a proof of
  `WellFormed` for them. `Prefix`, the observations, `InFrame` and
  `frame_lemma` take a subject, so they only describe programs of the
  fragment. The step function, `run`, `Steps` and the general lemma
  `frame_of_not_written` are defined for every program.
- **Memory.** Generic blocks, one value per block. A block can stand for a
  global, a caller's local or an existing heap allocation. Two pointers to the
  same existing block alias. A call creates a block for each parameter and local of
  the callee; at the return these blocks go out of scope. An access to a block
  that is not live faults. Identifiers are not reused, so a pointer to a block
  that went out of scope stays dangling. A lexical block creates its own
  locals with integer initializers and sweeps them when the block ends,
  including during return. The sweep releases the local and marks pointers
  to it in surviving values, including a pending return value. Function
  call cleanup still uses ordinary release.
- **Executions.** A deterministic small-step semantics whose continuation holds
  the call stack. Each step reports the reads and writes it performs, and the
  start and end of the lifetime of the callee's locals. An execution iterates
  the step function; a finite prefix is a finite sequence of steps. The two
  coincide (`steps_iff_run`).
- **Observations.** Exit on normal ends of the statement. Reach and Safety on
  every finite prefix, so they include the visits before a fault and inside a
  call that does not return. Safety covers run-time alarms and labelled
  assertions.
- **Abstract domains.** A `Domain` has states, a concretisation `γ` from a
  state to a set of memories, and the operations `filter`, `relate` and
  `reuse` on finite sets of blocks. `relate` may return `Top`. The laws are
  predicates on a domain: `filter` sound in its weak form (`filter` only
  forgets); `relate` sound (on a closed set, `filter` decomposes the state,
  and `relate` returns only blocks live in every memory the state covers);
  `filter` exact on a closed key of a state with a non-empty
  concretisation; `reuse` sound (the result covers every memory that agrees
  with an output memory on the written blocks and with a current memory
  elsewhere); `Extensional` (the operations depend on the members of a set
  of blocks only, so that closure, the decomposition and exactness do too).
  The product of two domains has the union of the two `relate`.
  No analysis is modelled: the laws are what an analysis is assumed to meet.

## Why the fragment is formulated this way

- **A bundle, not a hypothesis on each definition.** The observations take a
  `Subject` rather than a program, a statement and a separate proof. The
  fragment is then part of the type of every observation and of every theorem
  stated with them, so a later theorem cannot leave it out, and proofs read
  the conditions from `t.wf` when they need them. Definitions on raw programs
  would have to carry a proof argument that they do not use.
- **Execution stays on raw programs.** The step function, `run` and `Steps`
  do not depend on the fragment. Lemmas about executions, such as
  `steps_iff_run` and `frame_of_not_written`, need no fragment hypothesis, and
  the examples compute with `run` on the program itself.
- **A finite list of functions.** With functions given as a map from names,
  uniqueness of labels across all functions cannot be checked by computation.
  With a list, the label and name conditions are `List.Nodup` of concrete
  lists, and membership in the concrete list `Program.stmts`; statements have
  decidable equality, so `decide` checks the conditions for a given program.
- **Unique names.** A call takes the first definition with its name
  (`Program.lookup`). With distinct names, lookup by the name of an
  entry of the list returns that entry, so the other conditions, stated on
  the entries, are about the definitions that lookup returns.
- **Program labels apart from the observed statement.** The cache contract
  that the model serves is stated for any single-entry statement, with the
  function body as its first unit, so the observed statement must be allowed
  inside the program. The condition on the labels of the program is therefore
  stated without the observed statement (`labelsUnique`), and the observed
  statement is placed by a separate condition (`stmtLabels`) with two cases.
  In the first, `s` is a member of `Program.stmts`, the list of each body and
  the statements it contains. Its labels are then labels of the program and
  need no further condition. Membership compares statements, not labels, so a
  statement that only reuses a label of the program falls in the second case
  and is rejected there (`Checks/Fragment.lean`). In the second case, the
  labels of `s` and of the bodies are pairwise distinct. Both cases give that
  the labels of `s` are pairwise distinct (`WellFormed.stmt_labels_nodup`),
  and both are kept when passing to a statement inside `s`
  (`WellFormed.sub`). A proof that passes from a call to the body of its
  callee forms the new subject with `WellFormed.body`. Requiring instead that
  `s` be the body of a function would leave out the statements inside a body
  and the code outside the functions, which the examples use.
- **A rank for nonrecursion.** An existential rank gives later proofs a
  measure that decreases at each call. For a concrete program, the rank is
  given and `decide` checks it (`Checks/Fragment.lean`).

The proof of `frame_lemma` does not use the fragment conditions; they restrict
the programs that the lemma, as stated for the record, is about.

## Why the domain laws are formulated this way

- **Memories of the semantics.** `γ` maps a state to memories of the type `M`
  of the semantics, not to maps from blocks to values. A memory that
  exactness provides can then start an execution in the later theorems.
  Agreement on a set of blocks compares `Memory.load`.
- **Combination as a hypothesis.** The product lemma builds a memory that
  agrees with the current memory on the key and with a memory of the stored
  input elsewhere. The interface `Memory` has no operation that builds it, so
  the lemma takes `Combinable M` as a hypothesis, and
  `FunMem.combinable` proves it for `FunMem`. It is not added to `Memory`,
  whose laws the frame lemma relies on.
- **Finite sets as lists.** A set of blocks is a list, as Eva's sets of bases
  are finite. Membership is decidable, so combining two memories needs no
  classical choice. A domain receives the list itself, and the other laws
  do not prevent it from reading the order or the repetitions:
  `Checks.closed_needs_extensional` gives a domain that meets them in which
  `[0]` is closed and `[0, 0]` is not. The law `Extensional` excludes such
  domains. A type of sets with one representation per set, such as
  `Std.ExtTreeSet`, would make the law unnecessary. The model keeps lists:
  the existing files state membership, agreement and the frame lemma on
  lists, and Eva's obligation is then visible as a law, not hidden in a
  type. The match and product lemmas hold for every
  list and do not take the law. Under it, their hypotheses and conclusions
  are the same for every list with the members of the key: `closed_congr`,
  `decomposes_congr` and `exactOn_congr`, and `AgreeOn` uses membership
  only.
- **Exactness derived.** `FilterExact` is listed as a law, but the lemmas take
  `ExactOn`, exactness for one key and one state, and
  `filterExact_of_relateSound` derives the law from `relate` sound. The
  product lemma derives exactness of a product from the decomposition of each
  component, not from the exactness of each component: the two witnesses that
  component exactness gives need not be one memory.
- **Inclusion on concretisations.** The domains have no order. The inclusion
  of the filtered current input in the filtered stored input is stated on
  their concretisations; equality of the filtered states, which Eva tests,
  implies it.

## Entry construction

The footprint covers all reads and writes on finite prefixes, including
reads for assertions and attempted accesses that fault. The key contains the
reads and the possible exit writes other than certain full overwrites. A
matching memory and its producing witness must also agree on the liveness of
write targets and on allocation state. They use the same entry bindings.
Allocation agreement is reflexive, so each producing memory matches its own
entry. For `FunMem`, the agreement is equality of the next fresh identifier.
The projected match only supplies key agreement. The witness for write
liveness and allocation agreement is an additional obligation.

The construction transports Safety and Reach on all finite prefixes. On a
normal exit it gives a producing output covered by the Exit part, agreeing
with the current output on the possible exit writes. The frame theorem
computes the effect of prior sweeps on an issued block that the prefix
did not write. An unmarked pointer to an already-issued target needs no
rewrite. The hit theorem uses the current memory on all other blocks,
including absent bindings. Its no-rewrite premise rules out an
unmarked pointer to a recorded sweep target in the current frame on a
normal exit. Eva's admission and replay obligations remain open.

If the producer's saved state covers every visit to a label on the key,
`CacheEntry.shared_inner` transports that coverage to each matching
memory. A single concretisation witness agrees at that visit on the key
blocks issued in the matching memory at entry. A fresh local read by the
body may still belong to the lookup key. The witness may vary across visits. The fixture checks both
visits to the increment in `i = 0; while (i < 2) { L: i++; }`.

## A hit within one analysis

`CacheEntry.hit` is a conditional composition. It takes the joint
witness required by #36 for execution replay and by #37 for shared
Inner as a hypothesis. Under weak filter soundness, filtered inclusion
and stored-side exactness, `replayCompatible_iff_matches` says that
`ReplayCompatible` is equivalent to the existence of a single stored
witness for every current member, agreeing on key contents, write-target
liveness and allocator state. `valueDom_hit` constructs the witness for
the value domain using block fit and live write targets. For Eva's cvalue
this remains an open lookup obligation.

The two runs use the same subject and entry bindings. At each normal exit
the hit uses `ReuseSoundAt` on the stored witness over `W_exit` and the
unchanged current frame. `HitObservations` covers Reach and Safety on all
finite prefixes, with a valid assertion holding at every visit. The
checks include a hit on a member with a distinct frame and a larger key
that rejects that member even though its observations are covered.

With equality of the whole product, `whole_product_witness` gives the
current memory itself as a stored witness. The program and entry bindings
are common to both inputs. `hit_of_whole_product` still requires a sound
entry, no frame rewrite and `ReuseSoundAt` for each outcome.

For `w = x`, a projected match can succeed without closure in the current
input. A checked case has a stored input allowing either 0 or 1 for `x`,
and a current input also requiring `x = z`. The sound hit admits
`x = z = 0, w = 1`. A sound fresh exit on that current input entails
`w = z`.

The four contracts in `SideTables.lean` require equality at reported keyed
reads, run-wide invariance for each fixed observation, and a join at the
current hit position that covers the fresh contribution and existing
observations there and preserves coverage at other positions. Unsupported
accesses in producers or skipped work prevent storage or admission.
Completeness of the access relations, including nested work, is an open
Eva obligation. Coverage of the table inventory by the four contracts
is assumed.

## State queries on the callstack of a hit

A query names a statement, a full callstack and a position, before or after
the statement. The hit log has a line per hit: its callstack, the entry and
its inner part, and the state at the call with the blocks it binds. The
first line whose callstack ends the callstack of the query answers it, at
the point below the hit. The rules, in order:

- reconstruction disabled: no state;
- a block of the key: the shared inner state at the point;
- a block bound at the call and not in the footprint's writes: its value at
  the call, with the marks of any lexical sweeps;
- a block bound at the call that no write reaches before the point: the
  same;
- a block updated on every execution before the point: the shared inner
  state;
- any other block, including a local of the body: top.

`CacheEntry.query_sound` shows that each answer contains the content of the
block at each visit of the member at the point, and that the entry reports
the statement as reached. It takes the producer premises, the soundness of
the inner part for the producing input, the issuance of the bound blocks,
and the matching witness of the member as hypotheses. A visit before a
statement is a configuration about to execute it; a visit after it is the
first normal completion of that execution. Every write overwrites a whole
block, so the rule for updated blocks holds in the model; Eva must restrict
it to full overwrites and creations. The theorem covers the members of the
line that answers: with two lines on one callstack, the members of the
second are not covered (`Checks.same_callstack_first_line`). An inner part
with states on the key only, the writes of the footprint as possible writes
and no updated block is sound by coverage (`innerPartSound_of_key`).

## What the model leaves out

- Offsets into a block, arrays and structures, pointer arithmetic, and casts
  between pointers and integers.
- Recursion: the step function runs recursive programs, but the observations
  and `frame_lemma` take a `Subject`, whose program is nonrecursive.
- Eva's iteration strategy: there is no analyzer in the model. Abstract
  domains enter through their concretisation and their laws only; no domain
  of Eva is modelled, and the domains of `Checks/Domains.lean` are examples.
- An order on abstract states. The inclusion of the filtered inputs at the
  match is stated on their concretisations.
- Creation and release of heap allocations during a statement. Existing heap
  allocations are covered.
- Reads of uninitialized values (every local is declared with an initial
  value) and integer overflow (integers are unbounded).
