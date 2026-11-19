# State queries on the callstack of a hit

## Query answers on the callstack of a hit

**Kind.** Proved in Lean.

**Claim.** A state query names a statement, a full callstack, a position
(before or after the statement) and a block. The hit log has one line per
hit: its callstack, the entry used, the inner part of that entry, the
abstract state at the call and the blocks that this state binds. The first
line whose callstack ends the callstack of the query answers it, at the
point below the hit, by the first of these rules that applies:

1. reconstruction disabled: no state;
2. a block of the matching key: the shared inner state at the point;
3. a block bound at the call and outside the writes of the footprint (a
   frame block): its value in the call state, with the marks of any
   sequence of lexical sweeps;
4. a block bound at the call and outside the set of blocks possibly written
   before the point: the same;
5. a block written, created, released or swept on every execution before
   the point: the shared inner state at the point;
6. any other block, including a local of the body: top.

Let `m` be a member of the call state of the line that matches the entry.
At each visit of the point in `m`'s execution of the cached statement,
every answer contains the content of the block, and the entry reports the
statement as reached. An answer that contains a content is not bottom.

**Scope.** The model, with the same subject and entry bindings for the
member and its stored witness, whole-block writes, and the members of the
call state of the line. A visit is identified by a step count of the
member's execution of the cached statement:

- before a statement: the statement is about to execute, with the
  callstack of the point below the hit;
- after a statement: the first normal completion of that execution of the
  statement, with every configuration in between part of it. A statement
  left by `return` or by a fault has no visit after it.

The callstack of the query is the full callstack: the call sites inside the
body, innermost first, followed by the callstack of the line. The model runs
the body from its entry and not under the continuation of the caller;
`Checks.two_call_sites` ties the two lines of the example to the run of
`main` that makes both calls. The theorem makes no claim on an answer of no
state: with reconstruction disabled, or with no line for the callstack,
`query` returns `none`, and a client that needs a value takes top; that
last step is not a Lean definition. The theorem covers the members of the
line that answers, the first line whose callstack ends the callstack of the
query. When two lines have the same callstack, as for two hits of a call in
a loop, the members of the second are not covered, and
`Checks.same_callstack_first_line` shows an answer that misses one. Queries
on analysed callstacks, the join over callstacks and the publication of an
answer through a recorded join are not modelled.

**Declarations.** In [`Query.lean`](../../../lean/ReuseModel/Query.lean):
`QueryPoint`, `QueryPoint.below`, `trace`, `Config.Inside`, `AtPoint`,
`ValueSet.swept`, `Domain.valueOf`, `InnerPart`, `HitLine`,
`HitLine.answer`, `query`, `CacheEntry.InnerPartSound`,
`CacheEntry.innerPartSound_of_key`, `CacheEntry.replay_trace` and
`CacheEntry.query_sound`.

```text
@query_sound : ∀ {M : Type} [inst : Memory M] {d : Domain M} {log : List (HitLine d)} {line : HitLine d}
  {q : QueryPoint},
  List.find? (fun l => l.callstack.isSuffixOf q.callstack) log = some line →
    ∀ {a : AllocatorAgreement M},
      line.entry.ProducerSound →
        line.entry.Coverage →
          line.entry.KeyCovers →
            line.entry.InnerPartSound line.inner →
              (∀ (m : M), d.γ line.state m → ∀ (b : Block), b ∈ line.blocks → Memory.Issued m b) →
                ∀ {m : M},
                  d.γ line.state m →
                    line.entry.Matches a m →
                      ∀ {n : Nat},
                        AtPoint line.entry.subject { env := line.entry.env, mem := m } (q.below line.callstack) n →
                          line.entry.reached q.stmt ∧
                            ∀ (enabled : Bool) (b : Block) (vs : ValueSet),
                              query enabled log q b = some vs →
                                vs
                                  (Memory.load (trace line.entry.subject { env := line.entry.env, mem := m } n).snd.mem
                                    b)
'ReuseModel.CacheEntry.query_sound' depends on axioms: [propext, Quot.sound]
```

The definitions it uses:

```text
QueryPoint.below : QueryPoint → List Label → QueryPoint
@trace : {M : Type} → [Memory M] → Subject → State M → Nat → List Event × Config M
@Config.Inside : {M : Type} → Cont → Config M → Prop
@AtPoint : {M : Type} → [Memory M] → Subject → State M → QueryPoint → Nat → Prop
ValueSet.swept : ValueSet → ValueSet
@Domain.valueOf : {M : Type} → [Memory M] → (d : Domain M) → d.State → Block → ValueSet
@InnerPart : {M : Type} → Domain M → Type
@HitLine : {M : Type} → Domain M → Type
@HitLine.answer : {M : Type} → [Memory M] → {d : Domain M} → HitLine d → Bool → QueryPoint → Block → Option ValueSet
@query : {M : Type} → [Memory M] → {d : Domain M} → Bool → List (HitLine d) → QueryPoint → Block → Option ValueSet
@InnerPartSound : {M : Type} → [Memory M] → {d : Domain M} → CacheEntry d → InnerPart d → Prop
'ReuseModel.HitLine.answer' depends on axioms: [propext, Quot.sound]
'ReuseModel.query' depends on axioms: [propext, Quot.sound]
'ReuseModel.AtPoint' depends on axioms: [propext]
'ReuseModel.CacheEntry.InnerPartSound' depends on axioms: [propext]
```

An inner part with states on the key only, the writes of the footprint as
possible writes and no updated block meets `InnerPartSound` by coverage:

```text
@innerPartSound_of_key : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d}
  (state : QueryPoint → d.State),
  entry.Coverage →
    (∀ (w : M),
        d.γ entry.input w →
          ∀ (q : QueryPoint) (n : Nat),
            AtPoint entry.subject { env := entry.env, mem := w } q n →
              ∃ r,
                d.γ (state q) r ∧ AgreeOn entry.key r (trace entry.subject { env := entry.env, mem := w } n).snd.mem) →
      entry.InnerPartSound { state := state, mayWrite := fun x => entry.footprint.writes, updated := fun x => [] }
'ReuseModel.CacheEntry.innerPartSound_of_key' depends on axioms: [propext]
```

The replay lemma that the proof uses at each step count:

```text
@replay_trace : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {a : AllocatorAgreement M}
  {w m : M},
  ReplayAgreement a entry.key entry.footprint.writes w m →
    entry.Covers w →
      entry.KeyCovers →
        ∀ (n : Nat),
          ∃ m',
            trace entry.subject { env := entry.env, mem := m } n =
                ((trace entry.subject { env := entry.env, mem := w } n).fst,
                  (trace entry.subject { env := entry.env, mem := w } n).snd.withMem m') ∧
              AgreeOn (updatedBlocks (trace entry.subject { env := entry.env, mem := w } n).fst ++ entry.key)
                (trace entry.subject { env := entry.env, mem := w } n).snd.mem m'
'ReuseModel.CacheEntry.replay_trace' depends on axioms: [propext, Quot.sound]
```

**Hypotheses.**

| Premise | Kind and status |
|---|---|
| `M`, `d`, `log`, `line`, `q`, `a`, `m`, `n` | Model parameters. `m` is a member of the call state and `n` the step count of a visit. |
| `[Memory M]` | Model interface. Its laws are proved for `FunMem`. |
| `List.find? (fun l => l.callstack.isSuffixOf q.callstack) log = some line` | The selection that `query` makes, stated so that the line can be named. In Eva, the selection of the hit log line by callstack is an open OCaml obligation of #49. |
| `line.entry.ProducerSound`, `line.entry.Coverage`, `line.entry.KeyCovers` | Premises handed by [entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage). Proved for both fixtures. For Eva, the [producer obligations](cache-producer.md#producer-obligations-for-exit-reuse) remain open. The proof uses `ProducerSound.reach`, `Covers.accesses` and the first half of `KeyCovers` (the reads are in the key). It does not use `ProducerSound.exit`, `ProducerSound.safety`, `Covers.exitWrites`, `Covers.sure` or the second half of `KeyCovers`. The bundles are kept because they are the premises recorded for entry construction, which a caller with a sound entry already has. The unused fields restrict the entry only, not the members, the visits or the answers. |
| `line.entry.InnerPartSound line.inner` | Premise on the producer, introduced here. For each memory of the stored input and each visit at a point: the state at the point covers the visit on the key and on the blocks listed as updated; each block written so far is in the may-write set of the point; each block listed as updated has been written, created, released or swept so far. Proved for both fixtures. For Eva, an open OCaml obligation of #49. It extends the open coverage of producing visits in [Saved states and the public query](inner.md#saved-states-and-the-public-query). |
| `∀ m, d.γ line.state m → ∀ b ∈ line.blocks, Issued m b` | Every block that the line lists as bound is issued in every memory of the call state. Proved for both fixtures. For Eva, an open OCaml obligation of #49: the bound blocks of a line are bases bound in the state at the call. |
| `d.γ line.state m` | Local premise selecting the member. |
| `line.entry.Matches a m` | Premise handed by the hit: the joint matching witness. `CacheEntry.matches_of_projected` gives it from a projected match with `ReplayCompatible` ([Hit soundness](hit.md#hit-soundness)). `CacheEntry.whole_product_witness` gives it from equality of the whole product ([whole-product witness](whole-product.md#whole-product-equality-supplies-the-input-witness)). Constructed for both fixtures. For Eva, the lookup obligations of those entries remain open. |
| `AtPoint line.entry.subject ⟨line.entry.env, m⟩ (q.below line.callstack) n` | Local premise selecting the visit. |

**Depends on.** [Finite-prefix correspondence](entry.md#finite-prefix-correspondence)
for `run_agree` and `steps_iff_run`, and
[Frame lemma with lexical sweeps](frame.md#frame-lemma-with-lexical-sweeps)
for `frame_of_not_written`.

**Evidence.** The statements and axiom lines above are from the build of
the [checked tree](#evidence-for-these-entries).

## Status of each rule

| Rule | Answer | Status | Argument |
|---|---|---|---|
| Reconstruction disabled | No state | No claim | `query false` returns `none` for every block (`Checks.key_and_disabled_query`). |
| Block of the key | Shared inner state | Proved | `InnerPartSound.state` covers the producing visit on the key. The member and its witness agree on the key at every step (`replay_trace`). |
| Frame block | Value at the call with the marks of the sweeps | Proved | Coverage puts every write of the producing prefix in the writes of the footprint. The member has the same events. By `frame_of_not_written`, a block issued at the call and not written on the prefix holds its value at the call with the marks of the sweeps of the prefix. The premise on bound blocks gives the issuance. |
| Bound block, no write before the point | Same | Proved | As for a frame block, with `InnerPartSound.mayWrite` in place of coverage. |
| Updated on every execution before the point | Shared inner state | Proved, for whole-block writes | `InnerPartSound.updated` puts the block among the blocks updated by the producing prefix, on which the member and its witness agree (`replay_trace`). `InnerPartSound.state` covers the producing visit on that block. See the [known difference](#partial-write-of-one-byte). |
| Any other block, including a local of the body | Top | Answers top | Top contains every content. |

The stored inner value of a block outside the key is not an answer, and
neither is its join with the value at the call: the two-call and
overwritten-block checks below show that the stored value misses the
content of the member.

## Checked instances

The fixtures are in [`Query.lean`](../../../lean/Checks/Query.lean). Each
instance is the conclusion of `CacheEntry.query_sound` for its line, with
every premise proved or constructed in the file. Each answer is computed by
`rfl` and characterised exactly.

**Program.** Globals `x`, `g` and `r` are blocks 0, 1 and 2. The cached
statement is the body of `f`:

```c
f: L1: { L2: assert x;  L3: h(); }
h: L20: { L21: r = 0;  L22: ; }
main: L10: f() at 11;  g = 9;  r = 5;  f() at 16;
```

`main` starts with `x, g, r = 1, 4, 3`. The entry, stored by the call at
site 11 (whose own line in the log has the producing memory as its
member), has key `{x}`, writes `{r}`, stored input `x, g, r = 1, 4, 3` and
the inner part below. Before `r = 0;` (point `L21`, callstack `[3]` below
the hit): state `x, g, r = 1, 4, 3`, no possible write, nothing updated.
After it: state `x, g, r = 1, 4, 0`, possible write `{r}`, `{r}` updated.
Elsewhere: top, possible write `{r}`, nothing updated. The hit log has the
lines `[11]` with call state `x, g, r = 1, 4, 3` and `[16]` with call state
`x, g, r = 1, 9, 5`, both binding `{x, g, r}`.

| Declaration | Checked statement |
|---|---|
| `two_call_sites` | The run of `main` enters `L1` at step 2 with callstack `[11]` in the state of the first line, and at step 22 with callstack `[16]` in the state of the second. |
| `callState_eq` | The call state determines the memory: each line has one member. |
| An `example` on names | `x`, `g` and `r` evaluate to the cells of the member memory, and `f` runs with no binding of its own. |
| A second `example` on names | `y` evaluates to 1 in the producing memory and to 2 in the member of the local example; before `L41`, `t` is bound to block 1 and evaluates to 7. |
| `query_entry_premises`, `query_inner_sound` | Producer soundness, coverage, key coverage and soundness of the inner part, proved on the producing execution. |
| `query_member_matches` | Every member matches, with the producing memory as the witness. |
| `query_member_visits` | Each member is before `r = 0;` at step 5 and after it at step 6, with `g` and `r` at their call values at step 5 and `r = 0` at step 6. |
| `query_at_line` | `query_sound` at the line of a call site, before or after `r = 0;`. |

**Two-call example** (`two_call_query`). Before `r = 0;`, the query on `g`
answers exactly `{4}` on the callstack `[3, 11]` and exactly `{9}` on
`[3, 16]`, by the frame rule. Each answer contains the content of `g` at
the visit of that call. Negative check: the stored inner state holds `{4}`
for `g` at that point, which misses the 9 of the second call.

**Overwritten block** (`overwritten_query`). The stored inner state holds
`{3}` for `r` before `r = 0;`. On `[3, 16]` the query on `r` answers
exactly `{5}` before the write, by the rule for a block with no write
before the point, and exactly `{0}` after it, by the rule for updated
blocks. Each answer contains the content of `r` at the visit. Negative
checks: the stored `{3}` misses the 5 before the write, and the value at
the call, `{5}` with any sweep marks, misses the 0 after it.

**Key block and disabled reconstruction** (`key_and_disabled_query`). On
`[3, 16]` the query on `x` answers exactly `{1}`, the shared inner state.
With reconstruction disabled, every block answers no state. The entry
reports `L21` as reached.

**Local of the body** (`local_premises`, `local_at_line`, `local_query`).
A second statement, `L40: { int t = 7;  L41: ; }`, with a global `y` in
block 0 that it does not access. The local `t` is created in block 1. The
entry has an empty key and footprint and an inner part that is top
everywhere. The producer has `y = 1`; the member has `y = 2` and the same
next fresh block, so it matches. The line, at site 7, binds block 0 only.
Before `L41`, the query on `t` answers top and the content at the visit is
7. Negative check: the value of block 1 at the call, with any sweep marks,
is no value, which misses 7.

**Definitions pinned by checks.**

- `query_point_callstack`: at the steps of the visits before and after
  `r = 0;`, the points with an empty callstack below the hit have no
  visit. The callstack is part of the point in both positions.
- `frame_needs_sweeps`: in the fixture of `Checks/Sweeps.lean`, a frame
  block holds `ptr 2` at entry and `escaped 2` at the visit before label 4.
  The value at entry misses the content; the swept value contains it. This
  check uses `ValueSet.swept` directly: no instance through `query` has a
  sweep before the point.
- `same_callstack_first_line`: with the log `[16 with g = 4, 16 with g = 9]`,
  the query on `g` before `r = 0;` on `[3, 16]` answers `{4}` from the first
  line. The member of the second line visits that point with `g = 9`, which
  the answer misses.
- `after_ends_at_completion`: in
  `while (i < 2) { if (i == 0) A: i = 1; else B: i = 2; }`, there is a
  visit after A at step 3 and after B at step 7, and no visit after A at
  step 7. The completion of B, on the same continuation as A, is not a
  visit after A.

## Partial write of one byte

**Kind.** Known difference.

**Difference.** In the model, every write replaces a whole block with a
value computed from keyed reads. The member and its witness therefore agree
on each block written so far, which is what the rule for updated blocks
uses. In Eva, a write to part of a block keeps the other bytes from the
input without reading them. The #49 case: on a little-endian machine, a
16-bit unsigned block, the producer entering with `0x0100` and the member
with `0x0200`, a write of 1 to the low byte, then a full overwrite before
the return. Before the statement that follows the low-byte write, the
stored inner state holds 257 and the member holds 513. Applied to that
block, the rule for updated blocks would answer `{257}` and miss 513. The
block is written, so the frame rule and the rule for blocks with no write
before the point do not apply.

**Claim the model covers.** Blocks written as a whole, created, released
or swept on every execution before the point.

**Consequence for Eva.** The rule for updated blocks may list a block only
if every execution before the point fully overwrites or creates it after
any partial write. A block with a partial write answers top, recorded as a
loss of precision, which #49 accepts for this case.

**Evidence needed to extend coverage.** A model with offsets into a block
and writes of part of a block, with agreement stated per byte. Offsets are
listed as left out in [`lean/README.md`](../../../lean/README.md#what-the-model-leaves-out).

## What the Eva tickets must establish

- **#48 (Reach at a hit).** The theorem gives `entry.reached q.stmt` for
  every visited point, from the Reach part of the entry. #48 must deliver
  that part on the callstack of the hit, so that the callstack exists for
  queries and no statement of the body is reported dead on it.
- **#49 (hit log and state queries).** The hit log line: callstack, entry,
  inner part, state at the call and its bound blocks, and the point below
  the hit. The answer must cover every line whose callstack ends the
  callstack of the query, not only the first: the join of the answers of
  those lines, or one line per callstack whose state and entry cover all its
  hits (`Checks.same_callstack_first_line`). The rules in the order above,
  with no other source of answers: neither the stored value of a block
  outside the key nor its join with the value at the call. The premises
  `InnerPartSound` and the issuance of bound blocks for Eva's stored states,
  including the restriction of the updated rule to full overwrites and
  creations. A minimal implementation stores states on the key only, takes
  the writes of the footprint as the possible writes of every point and
  lists no updated block; `innerPartSound_of_key` shows that this inner part
  meets `InnerPartSound` by coverage. Every block outside the key and the
  frame then answers top. In the overwritten-block example this inner part
  answers top for `r` before and after the write, where the per-point data
  of the fixture gives `{5}` and `{0}`. The frame answer must apply the
  escaping of the sweeps performed before the point (`Locals_scoping`). With
  reconstruction disabled, or with state recording disabled for the function
  or the domain, no state, or top where a value is required. If an answer is
  published through a recorded join rather than computed at query time, the
  join must also meet the [side-table
  obligations](hit.md#side-table-obligations-for-skipped-work).
- **#50 (nested calls in the collector).** In the model, the callstack of a
  point inside the body includes the call sites in the body, and coverage
  and `InnerPartSound` range over the whole execution, nested calls
  included. On both paths for a nested call, fresh analysis and a child hit,
  the writes of the footprint and the possible-write and updated sets of
  each point must account for the effects of the child.
- **#51 (nested work under a hit).** A query on the callstack of a nested
  call below a hit is the case `[3, site]` of the fixture: the line of the
  hit is selected by suffix, and the point below it carries the sites of the
  nested calls. Several lines can match such a callstack: a hit of the
  nested call and a hit of an enclosing call. The answer must cover all of
  them, as for #49. The inner part must have points for the statements of
  the nested callees with those relative callstacks. A local of a nested
  callee answers top unless a rule above justifies another answer.

## Decisions that differ from the ticket text

- **Visits by step count.** A visit is a step count of `run`; every finite
  prefix is one by `steps_iff_run`. The point after a statement is its
  first normal completion, so a later completion on the same
  continuation is not a visit after it (`after_ends_at_completion`).
- **Key rule.** A block of the key takes the shared inner state with no
  condition that the call state binds it. `Matches` gives agreement of the
  member and its witness on every key block, bound or not, so the premise
  `shared_inner` uses for blocks issued at entry is not needed here. The
  theorem uses `Matches` directly rather than `shared_inner`.
- **Two justified rules for blocks outside the key.** "A justified answer"
  is two rules on data stored with the entry: no possible write before the
  point, and an update on every execution before the point. Other
  per-member data is not modelled; every other block answers top.
- **Premises of the entry.** The theorem takes `ProducerSound`, `Coverage`
  and `KeyCovers` rather than `Sound`, which also holds the reuse law of
  each outcome. It uses only some fields of these bundles, listed in the
  hypotheses table.
- **Lines on one callstack.** `query` answers from the first line whose
  callstack ends the callstack of the query. The ticket names no rule for
  several hits on one callstack; the theorem covers the members of the
  first line only (`Checks.same_callstack_first_line`).
- **Matching witness.** As in #38, `Matches` is a premise. The fixtures
  construct it; for a generic hit it comes from the entries cited in the
  hypotheses table.
- **Local of the body.** The two-call fixture cannot hold a local: the
  local of the first call takes block 3 and leaves the second call with
  next fresh block 4. Allocator agreement for `FunMem` is equality of the
  next fresh block, so the second call would not match. The local is
  checked on a second, smaller statement.

## Mutation evidence

Each change below was applied alone to a copy of the
[checked tree](#evidence-for-these-entries), then `lake build --wfail` was
run. Each run exited 1. The column "Fails in" names the first declaration
whose check failed.

**Hypotheses of `query_sound` and `innerPartSound_of_key`.** Removing a
premise from the statement makes the proof fail where it refers to the
premise. These runs show that the proof uses each premise, not that the
premise is necessary. The fixture changes in the last table show
necessity where they make a premise false.

| Scratch change | Fails in |
|---|---|
| Drop the selection premise | `query_sound` (selection of the line) |
| Drop `ProducerSound` | `query_sound` (reached statement) |
| Drop `Coverage` | `query_sound` (replay and frame rule) |
| Drop `KeyCovers` | `query_sound` (replay) |
| Drop `InnerPartSound` | `query_sound` (key, updated and no-write rules) |
| Drop the issuance of bound blocks | `query_sound` (frame and no-write rules) |
| Drop membership of the member in the call state | `query_sound` (frame and no-write rules) |
| Drop `Matches` | `query_sound` (replay) |
| Drop the visit | `query_sound` |
| Drop the `state` field of `InnerPartSound` | `innerPartSound_of_key`, `query_sound` (key and updated rules) |
| Drop the `mayWrite` field | `innerPartSound_of_key`, `query_sound` (no-write rule) |
| Drop the `updated` field | `innerPartSound_of_key`, `query_sound` (updated rule) |
| Drop `Coverage` from `innerPartSound_of_key` | `innerPartSound_of_key` (possible writes) |
| Drop the states on the key from `innerPartSound_of_key` | `innerPartSound_of_key` (the `state` field) |
| `innerPartSound_of_key` with no possible write | `innerPartSound_of_key` (a write of the prefix is outside the empty set) |

Some fixture changes in the last table make a premise false for the
fixture, and the proof of that premise fails: the issuance of bound blocks
(the line binds block 3), coverage (no writes in the footprint), key
coverage (empty key), producer soundness (`L21` not reached), and each
field of `InnerPartSound`: `state` (inner state before the write with
`r = 5`), `mayWrite` (no possible write after the write) and `updated`
(`r` updated before the write).

**Rules and definitions.** For these changes there are two runs. The first
builds the tree with the change. The second also replaces the proofs of
`query_sound`, `atPoint_transfer` and `reach_of_atPoint` with `sorry`, builds
`ReuseModel`, then checks `Checks/Query.lean`. In the second run the
generic theorem no longer constrains the rules, so a failure there comes
from the fixtures: an exact answer that changed, or a negative check that
the changed answer would contradict.

| Scratch change | Build with the change | Fixture checks with generic proofs replaced by `sorry` |
|---|---|---|
| Key rule for every block | `query_sound` | `two_call_query`, `overwritten_query`, `same_callstack_first_line`, `local_query`: a block outside the key takes the stored value, which the negative checks show misses the member's content |
| Key rule answers the value at the call | `query_sound` | `key_and_disabled_query` |
| Key rule answers top | `query_sound` | `key_and_disabled_query` |
| Frame rule without the condition on writes | `query_sound` | `overwritten_query`: `r` after the write answers `{5}`, which misses 0 |
| Frame rule without the condition that the block is bound | `query_sound` | `local_query`: `t` answers no value, which misses 7 |
| Frame rule without the marks of the sweeps | `query_sound` | `two_call_query`, `same_callstack_first_line`; `frame_needs_sweeps` shows that the value at entry misses the content |
| Frame rule answers the stored inner value | `query_sound` | `two_call_query`, `same_callstack_first_line`: `g` on `[3, 16]` answers `{4}`, which misses 9 |
| Frame rule answers top | `query_sound` | `two_call_query`, `same_callstack_first_line` |
| No-write rule without the may-write condition | `query_sound` | `overwritten_query`: `r` after the write answers `{5}`, which misses 0 |
| No-write rule without the condition that the block is bound | `query_sound` | `local_query`: `t` answers no value, which misses 7 |
| No-write rule answers the stored inner value | `query_sound` | `overwritten_query`: `r` before the write answers `{3}`, which misses 5 |
| No-write rule answers top | `query_sound` | `overwritten_query` |
| Updated rule for every block | `query_sound` | `local_query` |
| Updated rule answers the value at the call | `query_sound` | `overwritten_query`: `r` after the write answers `{5}`, which misses 0 |
| Updated rule answers top | `query_sound` | `overwritten_query` |
| Last rule answers bottom instead of top | `query_sound` | `local_query`: `t` answers bottom at a visit holding 7 |
| Disabled reconstruction answers the stored inner value | `query_sound` | `key_and_disabled_query` |
| Select the line by prefix instead of suffix of the callstack | `query_sound` | `two_call_query`, `overwritten_query`, `key_and_disabled_query`, `same_callstack_first_line` |
| Keep the full callstack instead of the point below the hit | `query_at_line` | `query_at_line`, `overwritten_query`, `key_and_disabled_query`, `local_at_line` |
| Drop the condition that the configurations between a statement and its completion are part of its execution | `atPoint_transfer` | `after_ends_at_completion`: the completion of B becomes a visit after A |
| Drop the callstack from a visit after a statement | `query_member_visits` (its proof term) | `query_point_callstack`: the point after `r = 0;` with an empty callstack now has a visit; `query_member_visits` and `after_ends_at_completion` fail by their proof terms |
| Drop the callstack from a visit before a statement | `query_member_visits` (its proof term) | `query_point_callstack`: the point with an empty callstack now has a visit; `query_member_visits`, `local_at_line` and `frame_needs_sweeps` fail by their proof terms |

Two unsound changes are detected by the fixtures through their exact
answers only, not by a contradiction: the key rule with the value at the
call, and the updated rule for every block. The first fails when a key
block is written before the point, as an exit write outside the sure
writes can be; the second when a block is written on some executions only.
Neither fixture has such a block. The changes that answer top are sound
and lose precision; the fixtures detect them by their exact answers.

**Fixture.** Each change below made `lake build --wfail` exit 1, with
errors in the listed declarations of `Checks/Query.lean`. The private
lemmas `producer_trace`, `producer_after_write`, `query_line_premises`,
`valueOf_call` and `valueOf_inner` support the public checks.

| Scratch change | Fails in |
|---|---|
| `x` holds 2 in the member memory | the `example` on names, `callState_eq`, `callState_queryMem`, `two_call_sites`, `producer_trace`, `valueOf_inner` |
| Swap the cells of `g` and `r` in the member memory | the `example` on names, `callState_eq`, `callState_queryMem`, `two_call_sites`, `producer_trace`, `query_member_visits`, `valueOf_call`, `valueOf_inner`, `two_call_query`, `overwritten_query` |
| Bind `g` to block 2 | the `example` on names, `two_call_sites` |
| Bind `r` to block 1 | the `example` on names, `two_call_sites`, `producer_trace`, `producer_after_write`, `query_member_visits`, `overwritten_query` |
| `main` sets `g = 8` | `two_call_sites` |
| `main` sets `r = 6` | `two_call_sites` |
| Swap the call states of the two lines | `two_call_query`, `overwritten_query`, `key_and_disabled_query` |
| Second line with `g = 4` | `two_call_query`, `overwritten_query`, `key_and_disabled_query` |
| Call state with next fresh block 4 | `callState_eq`, `callState_queryMem`, `two_call_sites`, `query_line_premises` |
| Line binds block 3 | `query_line_premises` |
| Empty key | `query_entry_premises`, `query_member_matches`, `key_and_disabled_query` |
| No writes in the footprint | `query_entry_premises`, `query_member_matches`, `overwritten_query` |
| `L21` not reached | `query_entry_premises` |
| Inner state before the write with `r = 5` | `producer_trace`, `valueOf_inner` |
| Inner state after the write with `r = 5` | `producer_trace`, `valueOf_inner` |
| `r` possibly written before the write | `overwritten_query` |
| No possible write after the write | `query_inner_sound`, `overwritten_query` |
| `r` not updated after the write | `query_inner_sound`, `overwritten_query` |
| `r` updated before the write | `query_inner_sound` |
| Line of the local binds block 1 | `local_at_line`, `local_query` |
| `t` initialised to 8 | the second `example` on names, `local_query` |
| Member of the local with two cells | `local_at_line`, `local_query` |
| Bind `y` to block 5 | the second `example` on names |

## Evidence for these entries

Tree of `lean/` `737f08643c484f08fa3b282bfb76e9d2d024b9bd` at
`b27792cd32c8ab261e396a650ede7bf2cfe934d2`. On a clean archive of that
tree, `cd lean && lake build --wfail` exited 0 with Lean 4.28.0. The axiom
guard accepted all printed declarations; every new declaration depends on
`propext` and `Quot.sound` at most. Each of the four Lean commits before it
on this branch also built on a clean archive. CI for this tree is pending.

The 60 build mutations and the 22 runs with the generic proofs replaced by
`sorry` above were run on copies of the same tree.
