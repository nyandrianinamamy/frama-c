# State queries on the callstack of a hit

## Query answers on the callstack of a hit

**Kind.** Proved in Lean.

**Claim.** A state query names a statement, a full callstack, a position
(before or after the statement) and a block. The hit log has one line per
hit: its callstack, the entry used, the inner part of that entry, the
abstract state at the call and the blocks that this state binds. A line
applies to the query when its callstack ends the callstack of the query;
lines whose callstacks have different lengths can all apply. Each line that
applies answers at the point below its hit, by the first of these rules that
applies:

1. reconstruction disabled: no state;
2. a block of the matching key: the shared inner state at the point;
3. a block bound at the call and outside the writes of the footprint (a
   frame block): its value in the call state, with the marks of any
   sequence of lexical sweeps;
4. a block bound at the call and absent from the possible writes recorded
   for the point, an over-approximation of the blocks written before it:
   the same;
5. a block listed as updated at the point: the shared inner state at the
   point;
6. any other block, including a local of the body: top.

The query joins the answers of the lines that apply: a content is in the
joined answer exactly when it is in the answer of one of them (`mem_query`).
With no line that applies, or when every line that applies answers no
state, the query reports no state. A set joined with an answer of no state
gives top; the model cannot produce that case, since the flag that disables
reconstruction is common to all lines.

Let `line` be a line that applies and `m` a member of its call state that
matches its entry. At each visit of the point below the hit in `m`'s
execution of the cached statement, every answer of the query contains the
content of the block, and the entry of the line reports the statement as
reached. An answer that contains a content is not bottom. With
reconstruction enabled, a query where a line applies returns a set
(`query_some` and `HitLine.answer_isSome`).

**Scope.** The model, with the same subject and entry bindings for the
member and its stored witness, whole-block writes, and the members of the
call states of the lines that apply. A visit is identified by a step count
of the member's execution of the cached statement:

- before a statement: the statement is about to execute, with the
  callstack of the point below the hit;
- after a statement: the first normal completion of that execution of the
  statement, with every configuration in between part of it. A statement
  left by `return` or by a fault has no visit after it.

The callstack of the query is the full callstack: the call sites inside the
body, innermost first, followed by the callstack of the line. The model runs
the body from its entry and not under the continuation of the caller;
`Checks.two_call_sites` and `Checks.loop_visits` tie the lines of the
examples to the runs that make the calls. The theorem makes no claim on an
answer of no state: with reconstruction disabled, or with no line that
applies, `query` returns `none`, and a client that needs a value takes top;
that last step is not a Lean definition. The theorem covers the members of
every line that applies, and takes the premises below for every such line;
its proof uses those of the line of the visit only. Queries on analysed
callstacks, the join over callstacks for a query that selects no callstack,
and the publication of an answer through a recorded join are not modelled.

**Declarations.** In [`Query.lean`](../../../lean/ReuseModel/Query.lean):
`QueryPoint`, `QueryPoint.below`, `trace`, `Config.Inside`, `AtPoint`,
`ValueSet.swept`, `Domain.valueOf`, `InnerPart`, `HitLine`,
`HitLine.answer`, `joinAnswer`, `joinAnswers`, `query`,
`joinAnswers_eq_none`, `mem_joinAnswers`, `joinAnswers_isSome`,
`mem_query`, `query_some`, `HitLine.answer_isSome`,
`CacheEntry.InnerPartSound`, `CacheEntry.innerPartSound_of_key`,
`CacheEntry.replay_trace`, `CacheEntry.answer_sound` and
`CacheEntry.query_sound`.

```text
@query_sound : ∀ {M : Type} [inst : Memory M] {d : Domain M} {log : List (HitLine d)} {q : QueryPoint}
  {a : AllocatorAgreement M},
  (∀ (line : HitLine d), line ∈ log → line.callstack.isSuffixOf q.callstack = true → line.entry.ProducerSound) →
    (∀ (line : HitLine d), line ∈ log → line.callstack.isSuffixOf q.callstack = true → line.entry.Coverage) →
      (∀ (line : HitLine d), line ∈ log → line.callstack.isSuffixOf q.callstack = true → line.entry.KeyCovers) →
        (∀ (line : HitLine d),
            line ∈ log → line.callstack.isSuffixOf q.callstack = true → line.entry.InnerPartSound line.inner) →
          (∀ (line : HitLine d),
              line ∈ log →
                line.callstack.isSuffixOf q.callstack = true →
                  ∀ (m : M), d.γ line.state m → ∀ (b : Block), b ∈ line.blocks → Memory.Issued m b) →
            ∀ {line : HitLine d},
              line ∈ log →
                line.callstack.isSuffixOf q.callstack = true →
                  ∀ {m : M},
                    d.γ line.state m →
                      line.entry.Matches a m →
                        ∀ {n : Nat},
                          AtPoint line.entry.subject { env := line.entry.env, mem := m } (q.below line.callstack) n →
                            line.entry.reached q.stmt ∧
                              ∀ (enabled : Bool) (b : Block) (vs : ValueSet),
                                query enabled log q b = some vs →
                                  vs
                                    (Memory.load
                                      (trace line.entry.subject { env := line.entry.env, mem := m } n).snd.mem b)
'ReuseModel.CacheEntry.query_sound' depends on axioms: [propext, Quot.sound]
```

The statement for one line, which `query_sound` applies to the line of the
visit:

```text
@answer_sound : ∀ {M : Type} [inst : Memory M] {d : Domain M} {line : HitLine d} {p : QueryPoint}
  {a : AllocatorAgreement M},
  line.entry.ProducerSound →
    line.entry.Coverage →
      line.entry.KeyCovers →
        line.entry.InnerPartSound line.inner →
          (∀ (m : M), d.γ line.state m → ∀ (b : Block), b ∈ line.blocks → Memory.Issued m b) →
            ∀ {m : M},
              d.γ line.state m →
                line.entry.Matches a m →
                  ∀ {n : Nat},
                    AtPoint line.entry.subject { env := line.entry.env, mem := m } p n →
                      line.entry.reached p.stmt ∧
                        ∀ (enabled : Bool) (b : Block) (vs : ValueSet),
                          line.answer enabled p b = some vs →
                            vs (Memory.load (trace line.entry.subject { env := line.entry.env, mem := m } n).snd.mem b)
'ReuseModel.CacheEntry.answer_sound' depends on axioms: [propext, Quot.sound]
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
joinAnswer : Option ValueSet → Option ValueSet → Option ValueSet
joinAnswers : List (Option ValueSet) → Option ValueSet
@query : {M : Type} → [Memory M] → {d : Domain M} → Bool → List (HitLine d) → QueryPoint → Block → Option ValueSet
@InnerPartSound : {M : Type} → [Memory M] → {d : Domain M} → CacheEntry d → InnerPart d → Prop
'ReuseModel.HitLine.answer' depends on axioms: [propext, Quot.sound]
'ReuseModel.joinAnswer' depends on axioms: [propext]
'ReuseModel.joinAnswers' depends on axioms: [propext]
'ReuseModel.query' depends on axioms: [propext, Quot.sound]
'ReuseModel.AtPoint' depends on axioms: [propext]
'ReuseModel.CacheEntry.InnerPartSound' depends on axioms: [propext]
```

The members of a joined answer, and the existence of an answer:

```text
@mem_query : ∀ {M : Type} [inst : Memory M] {d : Domain M} {enabled : Bool} {log : List (HitLine d)} {q : QueryPoint}
  {b : Block} {vs : ValueSet},
  query enabled log q b = some vs →
    ∀ (v : Option Value),
      vs v ↔
        ∃ line,
          line ∈ log ∧
            line.callstack.isSuffixOf q.callstack = true ∧
              (line.answer enabled (q.below line.callstack) b).getD ValueSet.top v
'ReuseModel.mem_query' depends on axioms: [propext, Quot.sound]
@query_some : ∀ {M : Type} [inst : Memory M] {d : Domain M} {enabled : Bool} {log : List (HitLine d)} {q : QueryPoint}
  {b : Block} {line : HitLine d},
  line ∈ log →
    line.callstack.isSuffixOf q.callstack = true →
      ∀ {x : ValueSet},
        line.answer enabled (q.below line.callstack) b = some x →
          ∃ vs, query enabled log q b = some vs ∧ ∀ (v : Option Value), x v → vs v
'ReuseModel.query_some' depends on axioms: [propext, Quot.sound]
@HitLine.answer_isSome : ∀ {M : Type} [inst : Memory M] {d : Domain M} (line : HitLine d) (q : QueryPoint) (b : Block),
  ∃ x, line.answer true q b = some x
'ReuseModel.HitLine.answer_isSome' depends on axioms: [propext, Quot.sound]
```

The lemmas on `joinAnswers` that these use:

```text
@joinAnswers_eq_none : ∀ {answers : List (Option ValueSet)},
  joinAnswers answers = none → ∀ (a : Option ValueSet), a ∈ answers → a = none
'ReuseModel.joinAnswers_eq_none' depends on axioms: [propext]
@mem_joinAnswers : ∀ {answers : List (Option ValueSet)} {vs : ValueSet},
  joinAnswers answers = some vs → ∀ (v : Option Value), vs v ↔ ∃ a, a ∈ answers ∧ a.getD ValueSet.top v
'ReuseModel.mem_joinAnswers' depends on axioms: [propext, Quot.sound]
@joinAnswers_isSome : ∀ {answers : List (Option ValueSet)} {x : ValueSet},
  some x ∈ answers → ∃ vs, joinAnswers answers = some vs
'ReuseModel.joinAnswers_isSome' depends on axioms: [propext]
```

An inner part with states on the key only, the writes of the footprint as
possible writes and no updated block meets `InnerPartSound` under two
premises: the states saved at each point cover the producing visits on the
key (the saved-state premise), and the footprint covers the writes of the
producing executions (coverage, for the possible-write field). Coverage
alone is not enough: `Checks.key_only_needs_states` gives an entry that
meets `Coverage` and a key-only inner part, with a state recording `x = 2`,
that fails `InnerPartSound`.

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

**Hypotheses.** Of `query_sound`:

| Premise | Kind and status |
|---|---|
| `M`, `d`, `log`, `q`, `a`, `line`, `m`, `n` | Model parameters. `line` is a line of the log, `m` a member of its call state and `n` the step count of a visit. |
| `[Memory M]` | Model interface. Its laws are proved for `FunMem`. |
| `∀ line ∈ log, line.callstack.isSuffixOf q.callstack → line.entry.ProducerSound`, and the same for `line.entry.Coverage` and `line.entry.KeyCovers` | Premises handed by [entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage), for every line that applies. Proved for every line of every log of the fixtures. For Eva, the [producer obligations](cache-producer.md#producer-obligations-for-exit-reuse) remain open. The proof uses them for the line of the visit only, and there it uses `ProducerSound.reach`, `Covers.accesses` and the first half of `KeyCovers` (the reads are in the key). It does not use `ProducerSound.exit`, `ProducerSound.safety`, `Covers.exitWrites`, `Covers.sure` or the second half of `KeyCovers`. The bundles are kept because they are the premises recorded for entry construction, which a caller with a sound entry already has. The unused fields restrict the entries only, not the members, the visits or the answers. |
| `∀ line ∈ log, line.callstack.isSuffixOf q.callstack → line.entry.InnerPartSound line.inner` | Premise on the producer, introduced here, for every line that applies. For each memory of the stored input and each visit at a point: the state at the point covers the visit on the key and on the blocks listed as updated; each block written so far is in the possible writes recorded for the point; each block listed as updated has been written, created, released or swept so far. Proved for every line of every log of the fixtures. For Eva, an open OCaml obligation of #49. It extends the open coverage of producing visits in [Saved states and the public query](inner.md#saved-states-and-the-public-query). |
| `∀ line ∈ log, line.callstack.isSuffixOf q.callstack → ∀ m, d.γ line.state m → ∀ b ∈ line.blocks, Issued m b` | Every block that a line that applies lists as bound is issued in every memory of its call state. Proved for every line of every log of the fixtures. For Eva, an open OCaml obligation of #49: the bound blocks of a line are bases bound in the state at the call. |
| `line ∈ log`, `line.callstack.isSuffixOf q.callstack = true` | Local premises selecting a line that applies. |
| `d.γ line.state m` | Local premise selecting the member. |
| `line.entry.Matches a m` | Premise handed by the hit: the joint matching witness. `CacheEntry.matches_of_projected` gives it from a projected match with `ReplayCompatible` ([Hit soundness](hit.md#hit-soundness)). `CacheEntry.whole_product_witness` gives it from equality of the whole product ([whole-product witness](whole-product.md#whole-product-equality-supplies-the-input-witness)). Constructed for every member of the fixtures. For Eva, the lookup obligations of those entries remain open. |
| `AtPoint line.entry.subject ⟨line.entry.env, m⟩ (q.below line.callstack) n` | Local premise selecting the visit. |

`answer_sound` takes the premises of one line, of the same kinds:
`line.entry.ProducerSound`, `line.entry.Coverage`, `line.entry.KeyCovers`,
`line.entry.InnerPartSound line.inner` and the issuance of the bound blocks
(premises on the entry and its producer, as above), and the local premises
`d.γ line.state m`, `line.entry.Matches a m` (handed by the hit, as above)
and a visit at the point `p`. `mem_query`, `query_some`,
`HitLine.answer_isSome` and the lemmas on `joinAnswers` have local premises
only: an equation on the result of `query` or `joinAnswers`, the membership
of a line or an answer, the suffix condition, and an equation on the answer
of a line.

**Depends on.** [Finite-prefix correspondence](entry.md#finite-prefix-correspondence)
for `run_agree` and `steps_iff_run`, and
[Frame lemma with lexical sweeps](frame.md#frame-lemma-with-lexical-sweeps)
for `frame_of_not_written`.

**Evidence.** The statements and axiom lines above are from the build of
the [checked tree](#evidence-for-these-entries).

## Status of each rule

| Rule | Answer | Status | Argument |
|---|---|---|---|
| Reconstruction disabled | No state | No claim | `query false` returns `none` for every block, on a callstack where one line applies (`Checks.key_and_disabled_query`) and where two apply (`Checks.no_state_queries`). |
| Block of the key | Shared inner state | Proved | `InnerPartSound.state` covers the producing visit on the key. The member and its witness agree on the key at every step (`replay_trace`). |
| Frame block | Value at the call with the marks of the sweeps | Proved | Coverage puts every write of the producing prefix in the writes of the footprint. The member has the same events. By `frame_of_not_written`, a block issued at the call and not written on the prefix holds its value at the call with the marks of the sweeps of the prefix. The premise on bound blocks gives the issuance. |
| Bound block absent from the recorded possible writes | Same | Proved | As for a frame block, with `InnerPartSound.mayWrite`, which puts every write of the producing prefix in the possible writes recorded for the point, in place of coverage. |
| Block listed as updated at the point | Shared inner state | Proved, for whole-block writes | The rule reads the recorded list. `InnerPartSound.updated` is the obligation on that list: each listed block is updated on every producing execution before the point, so it is among the blocks updated by the producing prefix, on which the member and its witness agree (`replay_trace`). `InnerPartSound.state` covers the producing visit on that block. A block updated on every execution but not listed answers top (`Checks.key_only_answers`). See the [known difference](#partial-write-of-one-byte). |
| Any other block, including a local of the body | Top | Answers top | Top contains every content. |
| Join of the lines that apply | Union of their answers | Proved | `mem_query`: the answer of each line that applies is contained in the joined answer. `query_sound` applies `answer_sound` to the line of the visit. |

The stored inner value of a block outside the key is not an answer, and
neither is its join with the value at the call: the two-call and
overwritten-block checks below show that the stored value misses the
content of the member.

## Checked instances

The fixtures are in [`Query.lean`](../../../lean/Checks/Query.lean). Each
instance is the conclusion of `CacheEntry.query_sound` at a line of its log,
with every premise proved or constructed in the file for every line of that
log (`LinePremises`). Each answer is computed by `rfl` and characterised
exactly; each joined answer of several lines is obtained through
`query_some`.

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
| `query_entry_premises`, `query_inner_sound` | Producer soundness, coverage and key coverage of the entry, and soundness of its inner part, proved on the producing execution. |
| `queryLine_premises` | Every line of a call of `f` meets the premises of `query_sound`. |
| `query_member_matches` | Every member matches, with the producing memory as the witness. |
| `query_member_visits` | Each member is before `r = 0;` at step 5 and after it at step 6, with `g` and `r` at their call values at step 5 and `r = 0` at step 6. |
| `query_at_line` | `query_sound` at the line of a call site of `f`, before or after `r = 0;`, in any log whose lines meet the premises. |

**Two-call example** (`two_call_query`). Before `r = 0;`, the query on `g`
answers exactly `{4}` on the callstack `[3, 11]` and exactly `{9}` on
`[3, 16]`, by the frame rule. Each answer contains the content of `g` at
the visit of that call. Negative check: the stored inner state holds `{4}`
for `g` at that point, which misses the 9 of the second call.

**Overwritten block** (`overwritten_query`). The stored inner state holds
`{3}` for `r` before `r = 0;`. On `[3, 16]` the query on `r` answers
exactly `{5}` before the write, by the rule for a block absent from the
recorded possible writes, and exactly `{0}` after it, by the rule for
listed updated blocks. Each answer contains the content of `r` at the
visit. Negative checks: the stored `{3}` misses the 5 before the write, and
the value at the call, `{5}` with any sweep marks, misses the 0 after it.

**Key block and disabled reconstruction** (`key_and_disabled_query`). On
`[3, 16]` the query on `x` answers exactly `{1}`, the shared inner state.
With reconstruction disabled, every block answers no state. The entry
reports `L21` as reached.

**Several lines on the callstack of a query.** A second program calls `f`
at site 11 and then in a loop at site 16:

```c
loopMain: L10: f() at 11;  L12: while (x) { f() at 16;  g = 9;  r = 5; }
```

| Declaration | Checked statement |
|---|---|
| `loop_visits` | From `x, g, r = 1, 4, 3`, the first three visits before `r = 0;` are at steps 7, 23 and 44 (no other step below 45 is one), on the callstacks `[3, 11]`, `[3, 16]` and `[3, 16]`, with `g = 4`, 4 and 9. The run enters `f` at steps 2, 18 and 39 and `h` at steps 6, 22 and 43, in the states `x, g, r = 1, 4, 3`, `1, 4, 0` and `1, 9, 5`. |
| `same_callstack_join` | The log when both calls at site 16 hit the entry of `f`: lines `[11]` with `g, r = 4, 3`, `[16]` with `4, 0` and `[16]` with `9, 5`. Before `r = 0;` on `[3, 16]`, the query on `g` joins the two lines on `[16]` and answers exactly `{4, 9}`; it contains 4 and 9, the content of `g` at the visit of each member. On `[3, 11]` it answers exactly `{4}`. |
| `no_state_queries` | On that log, with reconstruction disabled, the query on `[3, 16]`, where two lines apply, reports no state for every block; a query on `[3, 12]`, which no line ends, reports no state. |
| `callee_entry_premises`, `calleeLine_premises`, `callee_member` | An entry for the body of `h`, stored by its call with `x, g, r = 1, 4, 3`: no read, so an empty key, and `r` written. Its inner part has states on the key only, sound by `innerPartSound_of_key`. Every line of a call of `h` meets the premises; every call state matches the entry, and a member is before `r = 0;` at step 1 of the body of `h`, with `g` at its call value. |
| `nested_suffix_join` | The log when the first call at site 16 is analysed and its call of `h` hits the entry of `h`, and the second call at site 16 hits the entry of `f`: lines `[11]`, `[3, 16]` (for `h`, with `g = 4`) and `[16]` (with `g = 9`). Both `[3, 16]` and `[16]` end the callstack `[3, 16]`. The line of `h` answers `{4}` at the point below its hit, with the empty callstack; the line of `f` answers `{9}` at the point with the callstack `[3]`. The query on `g` answers exactly `{4, 9}` and contains the content of `g` at the visit of each member. |
| `three_lines_join` | A log of three lines that all apply to `[3, 16]`: `f` with `g = 9`, `h` with `g = 4`, `f` with `g = 7`. The query on `g` before `r = 0;` answers exactly `{9, 4, 7}` and contains the content of `g` at the visit of each member. Each line gives a value that the others do not. The log is not that of one run. |

**Inner parts with states on the key only.**

| Declaration | Checked statement |
|---|---|
| `key_only_needs_states` | The entry of `f` meets `Coverage`, and the inner part with the state `x = 2` at every point, the writes of the footprint as possible writes and no updated block does not meet `InnerPartSound`: the producer visits `r = 0;` with `x = 1`. |
| `key_inner_sound` | The projection of the inner part of `f` on the key meets `InnerPartSound` by `innerPartSound_of_key`, with both premises: its states cover the producing visits on the key, by `query_inner_sound`, and coverage. |
| `key_only_answers` | At every producing visit after `r = 0;`, `r` has been updated; the projection does not list it. With a line of that inner part on `[16]` and `g, r = 9, 5`, the query on `r` answers top after the write and before it, where the line of the stored inner part answers `{0}` and `{5}`. The line meets the premises, and `x` answers exactly `{1}`. |

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
block is written, so the frame rule and the rule for blocks absent from the
recorded possible writes do not apply.

**Claim the model covers.** Blocks listed as updated at the point, each
written as a whole, created, released or swept on every execution before
the point.

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
  the hit. The Lean query joins the answers of the lines whose callstack
  ends the callstack of the query. Eva's obligation is that its answer on a
  hit callstack is the join over the hit lines of that callstack, each line
  answering at the point below its hit (`Checks.same_callstack_join`,
  `Checks.nested_suffix_join`). The rules of one line in the order above,
  with no other source of answers: neither the stored value of a block
  outside the key nor its join with the value at the call. The premises
  `InnerPartSound` and the issuance of bound blocks for Eva's stored
  states, for every hit line. The rule for updated blocks answers from the
  recorded list: Eva may list a block only if every execution before the
  point updates it, restricted to full overwrites and creations, and a
  block it does not list answers top. The rule for blocks with no write
  before the point reads the recorded possible writes, which must contain
  every block written before the point. A minimal implementation stores
  states on the key only, takes the writes of the footprint as the
  possible writes of every point and lists no updated block.
  `innerPartSound_of_key` shows that this inner part meets `InnerPartSound`
  under two premises: the states saved at each point cover the producing
  visits on the key, and the footprint covers the writes, for the
  possible-write field. Coverage alone is not enough
  (`Checks.key_only_needs_states`). Every block outside the key and the
  frame then answers top. In the overwritten-block example this inner part
  answers top for `r` before and after the write, where the per-point data
  of the fixture gives `{5}` and `{0}` (`Checks.key_only_answers`). The
  frame answer must apply the escaping of the sweeps performed before the
  point (`Locals_scoping`). With reconstruction disabled, or with state
  recording disabled for the function or the domain, no state, or top
  where a value is required. If an answer is published through a recorded
  join rather than computed at query time, the join must also meet the
  [side-table obligations](hit.md#side-table-obligations-for-skipped-work).
- **#50 (nested calls in the collector).** In the model, the callstack of a
  point inside the body includes the call sites in the body, and coverage
  and `InnerPartSound` range over the whole execution, nested calls
  included. On both paths for a nested call, fresh analysis and a child hit,
  the writes of the footprint and the possible-write and updated sets of
  each point must account for the effects of the child.
- **#51 (nested work under a hit).** A query on the callstack of a nested
  call below a hit is the case `[3, site]` of the fixture: the lines of the
  hits are selected by suffix, and the point below each carries the sites
  of the nested calls. Several lines can match such a callstack: a hit of
  the nested call and a hit of an enclosing call. The Lean query joins them
  (`Checks.nested_suffix_join`), and #51 must keep that join. The inner
  part must have points for the statements of the nested callees with
  those relative callstacks. A local of a nested callee answers top unless
  a rule above justifies another answer.

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
  is two rules on data stored with the entry: absence from the possible
  writes recorded for the point, and membership in the list of blocks
  updated at the point. `InnerPartSound` is the obligation on the recorded
  sets. Other per-member data is not modelled; every other block answers
  top.
- **Premises of the entry.** The theorem takes `ProducerSound`, `Coverage`
  and `KeyCovers` rather than `Sound`, which also holds the reuse law of
  each outcome. It uses only some fields of these bundles, listed in the
  hypotheses table.
- **Join of the lines that apply.** The ticket names no rule for several
  hits whose callstacks end the callstack of a query. `query` joins the
  answers of all of them, lines on one callstack and lines whose callstacks
  have different lengths included. The join of answers that are all no
  state is no state, so that disabled reconstruction reports no state on
  any log; a set joined with no state gives top, a case the model cannot
  produce.
- **Premises for every line that applies.** `query_sound` takes the
  premises on the entry, the inner part and the bound blocks of every line
  that applies, so that one statement covers every visit of the query. Its
  proof uses those of the line of the visit only. `answer_sound` is the
  statement for one line.
- **Matching witness.** As in #38, `Matches` is a premise. The fixtures
  construct it; for a generic hit it comes from the entries cited in the
  hypotheses table.
- **Local of the body.** The two-call fixture cannot hold a local: the
  local of the first call takes block 3 and leaves the second call with
  next fresh block 4. Allocator agreement for `FunMem` is equality of the
  next fresh block, so the second call would not match. The local is
  checked on a second, smaller statement.

## Mutation evidence

Each change below was applied alone, as a text substitution, to a copy of
the [checked tree](#evidence-for-these-entries), then `lake build --wfail`
was run. Each run exited 1; a control run with no change exited 0. The
column "Fails in" names the declarations with errors in the first module
that failed.

**Hypotheses of `query_sound`, `answer_sound` and `innerPartSound_of_key`.**
Removing a premise from the statement makes the proof fail where it refers
to the premise. These runs show that the proof uses each premise, not that
the premise is necessary. The fixture changes in the last tables show
necessity where they make a premise false.

| Scratch change | Fails in |
|---|---|
| `query_sound` without `ProducerSound` | `query_sound` |
| `query_sound` without `Coverage` | `query_sound` |
| `query_sound` without `KeyCovers` | `query_sound` |
| `query_sound` without `InnerPartSound` | `query_sound` |
| `query_sound` without the issuance of bound blocks | `query_sound` |
| `query_sound` without the membership of the line in the log | `query_sound` |
| `query_sound` without the suffix premise | `query_sound` |
| `query_sound` without the membership of the member in the call state | `query_sound` |
| `query_sound` without `Matches` | `query_sound` |
| `query_sound` without the visit | `query_sound` |
| `answer_sound` without `ProducerSound` | `answer_sound`, `query_sound` |
| `answer_sound` without `Coverage` | `answer_sound`, `query_sound` |
| `answer_sound` without `KeyCovers` | `answer_sound`, `query_sound` |
| `answer_sound` without `InnerPartSound` | `answer_sound`, `query_sound` |
| `answer_sound` without the issuance of bound blocks | `answer_sound`, `query_sound` |
| `answer_sound` without the membership of the member in the call state | `answer_sound`, `query_sound` |
| `answer_sound` without `Matches` | `answer_sound`, `query_sound` |
| `answer_sound` without the visit | `answer_sound`, `query_sound` |
| `InnerPartSound` without its `state` field | `innerPartSound_of_key`, `answer_sound` |
| `InnerPartSound` without its `mayWrite` field | `innerPartSound_of_key`, `answer_sound` |
| `InnerPartSound` without its `updated` field | `innerPartSound_of_key`, `answer_sound` |
| `innerPartSound_of_key` without `Coverage` | `innerPartSound_of_key` |
| `innerPartSound_of_key` without the states on the key | `innerPartSound_of_key` |
| `innerPartSound_of_key` with no possible write | `innerPartSound_of_key` |

Some fixture changes in the last tables make a premise false for the
fixture, and the proof of that premise fails: the issuance of bound blocks
(the line binds block 3), coverage (no writes in the footprint, for `f` and
for `h`), key coverage (empty key), producer soundness (`L21` not reached,
for `f` and for `h`), and each field of `InnerPartSound`: `state` (inner
state before the write with `r = 5`), `mayWrite` (no possible write after
the write) and `updated` (`r` updated before the write). For the key-only
inner part, a state that does not cover the producing visits on the key
makes `key_inner_sound` fail, and a state recording `x = 1` makes the
counter-example `key_only_needs_states` fail.

**Rules, join and definitions.** For these changes there are two runs. The
first builds the tree with the change. The second also replaces the proofs
of `answer_sound`, `query_sound`, `atPoint_transfer`, `reach_of_atPoint`,
`mem_query`, `query_some`, `HitLine.answer_isSome` and the three lemmas on
`joinAnswers` with `sorry`, builds `ReuseModel` with `Checks.Entries` and
`Checks.Sweeps`, then checks `Checks/Query.lean`. A control run of the
second kind with no change succeeded. In the second run the generic
theorems no longer constrain the rules or the join, so a failure there
comes from the fixtures: an exact answer that changed, or a negative check
that the changed answer would contradict.

| Scratch change | Build with the change | Fixture checks with generic proofs replaced by `sorry` |
|---|---|---|
| Key rule for every block | `answer_sound` | `two_call_query`, `overwritten_query`, `same_callstack_join`, `nested_suffix_join`, `three_lines_join`, `key_only_answers`, `local_query`: a block outside the key takes the stored value, which the negative checks show misses the content of the member |
| Key rule answers the value at the call | `answer_sound` | `key_and_disabled_query`, `key_only_answers` |
| Key rule answers top | `answer_sound` | `key_and_disabled_query`, `key_only_answers` |
| Frame rule without the condition on writes | `answer_sound` | `overwritten_query`, `key_only_answers`: `r` after the write answers `{5}`, which misses 0 |
| Frame rule without the condition that the block is bound | `answer_sound` | `local_query`: `t` answers no value, which misses 7 |
| Frame rule without the marks of the sweeps | `answer_sound` | `two_call_query`, `same_callstack_join`, `nested_suffix_join`, `three_lines_join`; `frame_needs_sweeps` shows that the value at entry misses the content |
| Frame rule answers the stored inner value | `answer_sound` | `two_call_query`, `same_callstack_join`, `nested_suffix_join`, `three_lines_join`: `g` on `[3, 16]` answers `{4}`, which misses 9 |
| Frame rule answers top | `answer_sound` | `two_call_query`, `same_callstack_join`, `nested_suffix_join`, `three_lines_join` |
| No-write rule without the may-write condition | `answer_sound` | `overwritten_query`, `key_only_answers`: `r` after the write answers `{5}`, which misses 0 |
| No-write rule without the condition that the block is bound | `answer_sound` | `local_query`: `t` answers no value, which misses 7 |
| No-write rule answers the stored inner value | `answer_sound` | `overwritten_query`: `r` before the write answers `{3}`, which misses 5 |
| No-write rule answers top | `answer_sound` | `overwritten_query` |
| Updated rule for every block | `answer_sound` | `key_only_answers`, `local_query` |
| Updated rule answers the value at the call | `answer_sound` | `overwritten_query`: `r` after the write answers `{5}`, which misses 0 |
| Updated rule answers top | `answer_sound` | `overwritten_query` |
| Last rule answers bottom instead of top | `answer_sound` | `key_only_answers`, `local_query`: `t` answers bottom at a visit holding 7 |
| Disabled reconstruction answers the stored inner value | `answer_sound` | `key_and_disabled_query`, `no_state_queries` |
| Select the lines by prefix instead of suffix of the callstack | `mem_query`, `query_some` | `two_call_query`, `overwritten_query`, `key_and_disabled_query`, `same_callstack_join`, `nested_suffix_join`, `three_lines_join`, `key_only_answers` |
| Keep the full callstack instead of the point below the hit | `mem_query`, `query_some` | `overwritten_query`, `key_and_disabled_query`, `key_only_answers` |
| Drop the condition that the configurations between a statement and its completion are part of its execution | `atPoint_transfer` | `producer_point`, `query_member_visits`, `query_point_callstack`, `after_ends_at_completion`: the completion of B becomes a visit after A |
| Drop the callstack from a visit after a statement | `atPoint_transfer` | `producer_point`, `query_member_visits`, `query_point_callstack`, `after_ends_at_completion`: the point after `r = 0;` with an empty callstack now has a visit |
| Drop the callstack from a visit before a statement | `atPoint_transfer`, `reach_of_atPoint` | `producer_point`, `query_member_visits`, `query_point_callstack`, `callee_member`, `local_at_line`, `frame_needs_sweeps`: the point before `r = 0;` with an empty callstack now has a visit |
| Join: the first line that applies only | `joinAnswers_eq_none`, `mem_joinAnswers`, `joinAnswers_isSome` | `same_callstack_join`, `nested_suffix_join`, `three_lines_join`: on `[3, 16]`, `g` answers `{4}`, which misses 9 |
| Join: the last line that applies only | `joinAnswers_eq_none`, `mem_joinAnswers`, `joinAnswers_isSome` | `same_callstack_join`, `nested_suffix_join`, `three_lines_join`: on `[3, 16]`, `g` answers `{9}`, which misses 4 |
| Join: the first two lines that apply only | `joinAnswers_eq_none`, `mem_joinAnswers`, `joinAnswers_isSome` | `three_lines_join`: the third line, with `g = 7`, is left out |
| No state when the log has more than two lines | `mem_query`, `query_some` | `same_callstack_join`, `nested_suffix_join`, `three_lines_join`: no state on the logs of three lines |
| No state when three or more lines apply | `mem_query`, `query_some` | `three_lines_join`: no state where three lines apply |
| The lines with the longest callstack only | `mem_query`, `query_some` | `nested_suffix_join`, `three_lines_join`: only the line of `h` answers, and 9 is missed |
| The lines with the shortest callstack only | `mem_query`, `query_some` | `nested_suffix_join`, `three_lines_join`: only the lines of `f` answer, and 4 is missed |
| Join of two sets answers top | `mem_joinAnswers` | `same_callstack_join`, `nested_suffix_join`, `three_lines_join` |
| Join of two sets is their intersection | `mem_joinAnswers` | `same_callstack_join`, `nested_suffix_join`, `three_lines_join`: the intersection of `{4}` and `{9}` is empty and misses both |
| A set and no state join to no state | `joinAnswers_eq_none`, `mem_joinAnswers`, `joinAnswers_isSome` | none: no fixture joins a set with no state, which the model cannot produce |
| Two answers of no state join to top | `mem_joinAnswers` | `no_state_queries`: a disabled query where two lines apply answers top |
| The empty list joins to top | `mem_joinAnswers` | `no_state_queries`: a query where no line applies answers top |

Two unsound changes are detected by the fixtures through their exact
answers only, not by a contradiction: the key rule with the value at the
call, and the updated rule for every block. The first fails when a key
block is written before the point, as an exit write outside the sure
writes can be; the second when a block is written on some executions only.
No fixture has such a block. The changes that answer top, the join of two
sets among them, are sound and lose precision; the fixtures detect them by
their exact answers. The join of a set with no state is not reached by any fixture:
the model cannot produce it, since the flag that disables reconstruction is
common to the lines; the lemmas on `joinAnswers` fail with that change.

**Fixture.** Each change below made `lake build --wfail` exit 1, with
errors in the listed declarations of `Checks/Query.lean`. The private
lemmas `producer_trace`, `producer_after_write`, `producer_point`,
`callState_issued`, `callee_trace`, `valueOf_call` and `valueOf_inner`
support the public checks.

| Scratch change | Fails in |
|---|---|
| `x` holds 2 in the member memory | the `example` on names, `callState_eq`, `callState_queryMem`, `two_call_sites`, `producer_trace`, `valueOf_inner`, `loop_visits`, `key_only_needs_states`, `key_only_answers` |
| Swap the cells of `g` and `r` in the member memory | the `example` on names, `callState_eq`, `callState_queryMem`, `two_call_sites`, `producer_trace`, `query_member_visits`, `valueOf_call`, `valueOf_inner`, `two_call_query`, `overwritten_query`, `loop_visits`, `same_callstack_join`, `callee_member`, `nested_suffix_join`, `key_only_answers` |
| Bind `g` to block 2 | the `example` on names, `two_call_sites`, `loop_visits` |
| Bind `r` to block 1 | the `example` on names, `two_call_sites`, `producer_trace`, `producer_after_write`, `query_member_visits`, `overwritten_query`, `loop_visits`, `callee_trace` |
| `main` sets `g = 8` | `two_call_sites` |
| `main` sets `r = 6` | `two_call_sites` |
| Swap the call states of the two lines | `two_call_query`, `overwritten_query`, `key_and_disabled_query` |
| Second line with `g = 4` | `two_call_query`, `overwritten_query`, `key_and_disabled_query` |
| Call state with next fresh block 4 | `callState_eq`, `callState_queryMem`, `two_call_sites`, `callState_issued`, `loop_visits` |
| Line of `f` binds block 3 | `queryLine_premises` |
| Empty key | `query_entry_premises`, `query_member_matches`, `key_and_disabled_query`, `key_only_needs_states`, `key_only_answers` |
| No writes in the footprint | `query_entry_premises`, `query_member_matches`, `overwritten_query`, `key_only_answers` |
| `L21` not reached | `query_entry_premises` |
| Inner state before the write with `r = 5` | `producer_trace`, `valueOf_inner`, `key_only_answers` |
| Inner state after the write with `r = 5` | `producer_trace`, `valueOf_inner` |
| `r` possibly written before the write | `overwritten_query` |
| No possible write after the write | `query_inner_sound`, `overwritten_query` |
| `r` not updated after the write | `query_inner_sound`, `overwritten_query`, `key_only_answers` |
| `r` updated before the write | `query_inner_sound` |
| Line of the local binds block 1 | `local_at_line`, `local_query` |
| `t` initialised to 8 | the second `example` on names, `local_query` |
| Member of the local with two cells | `local_at_line`, `local_query` |
| Bind `y` to block 5 | the second `example` on names |
| `loopMain` sets `g = 8` | `loop_visits` |
| Loop condition false | `loop_visits` |
| `loopLog`: first line on `[16]` with `g = 9` | `same_callstack_join` |
| `loopLog`: first line on `[16]` moved to `[11]` | `same_callstack_join` |
| `nestedLog`: line of `h` with `g = 9` | `nested_suffix_join` |
| `nestedLog`: line of `h` on `[3, 11]` | `nested_suffix_join` |
| `threeLog`: third line with `g = 4` | `three_lines_join` |
| Entry of `h` with key `{r}` | `callee_entry_premises`, `callee_member` |
| Entry of `h` with no writes | `callee_entry_premises`, `callee_member` |
| Entry of `h` without `L21` reached | `callee_entry_premises` |
| Counter-example with a state recording `x = 1` | `key_only_needs_states` |
| Key-only inner part lists `r` as updated after the write | `key_inner_sound`, `key_only_answers` |
| `keyInner` with the state `x = 2` in place of the projection | `key_inner_sound`, `key_only_answers` |

## Evidence for these entries

Tree of `lean/` `3380facecc96fb5ed308e77912bd162db667a9f2` at
`6f9f50ce9fd98294bbb4307ce173e570fd4a9c26`. On a clean archive of that
tree, `cd lean && lake build --wfail` exited 0 with Lean 4.28.0. The axiom
guard accepted all printed declarations; every new declaration depends on
`propext` and `Quot.sound` at most. Each Lean commit of this branch since
`e01f7a2e78` also built on a clean archive. The output of `#check`,
`#print axioms` and `#check_axioms` for the declarations of the earlier
entries is the same as on `e01f7a2e78`. CI for this tree is pending.

The 94 build mutations and the 34 runs with the generic proofs replaced by
`sorry` above were run on copies of the same tree.
