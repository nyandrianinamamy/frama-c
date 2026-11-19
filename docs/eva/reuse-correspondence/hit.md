# A hit within one analysis

[Nested call collection](nested-calls.md) records the contributions of
skipped children using the winning entry, conditional on its coverage and
the admission checks. Before #47, the lookup rejects enclosing hits that
would skip those children or inline work, as `nested-delivery`. The
theorem below relies on a sound model entry, whose replay premises remain
open for Eva's reduced key and surviving overlay.

## Hit soundness

**Kind.** Proved in Lean.

**Claim.** Given its joint replay witness and the other premises below,
the projected hit covers every normal outcome for each concrete memory
covered by the current input with the state returned by
`reuse W_exit`. The concrete exit agrees with that input outside
`W_exit`. The condition on current frame holders applies to the
actual normal-exit trace. Reach and Safety cover every finite prefix,
including a prefix of a nonterminating execution or one ending in a
fault. A valid status means absence of the assertion from the possible
violations, and its expression holds on every visit. The theorem permits
extra reached labels and possible violations.

**Depends on.** [Match lemma](matching.md#match-lemma),
[sound entries](entry.md#sound-entry-from-producer-soundness-and-coverage),
and [frame preservation](frame.md#frame-lemma-with-lexical-sweeps).

`CacheEntry.hit` is a conditional composition. It takes the joint
witness required by #36 for execution replay and by #37 for shared Inner
as a hypothesis. Weak `filter` soundness, filtered inclusion and
`ExactOn` give a key-content witness. Under these three premises,
`replayCompatible_iff_matches` proves that `ReplayCompatible` is
equivalent to having one stored witness for every covered current member
that agrees on key contents, liveness on `W`, and allocator state.
`valueDom_hit` discharges this hypothesis for the value domain using
block fit and liveness of write targets. For Eva's cvalue, constructing
the joint witness remains an open lookup obligation.

```lean
∃ w, d.γ entry.input w ∧ ReplayAgreement a entry.key entry.footprint.writes w m
```

For a normal exit, `Sound.matched` supplies a stored output witness at
the same outcome with agreement on `W_exit`, and coverage excludes
ordinary writes elsewhere on that trace. For an initially live block
outside the overlay, `frame_of_not_written` gives the entry value
transformed by the trace's sweeps. `exit_preserves_absence` covers any
block with no entry value, including an already released binding and an
unissued identifier later allocated and released inside the body.
`exit_frame_iff` characterizes equality of all off-overlay loads by the
current holders' no-rewrite condition. Load equality also includes
absence on `W_exit` where the stored witness and actual exit both have
no binding. `hit_of_matches` passes the actual current input and the
stored output witness to the law for this overlay.

**Hypotheses.**

| Premise | Kind and status |
|---|---|
| `M : Type`, `d : Domain M`, `entry : CacheEntry d`, `cur : d.State`, `m : M` | Model parameters. `entry.subject` contains the fragment proof. Its program, statement and `entry.env` are common to the producing and current executions. Establishing that these identify the same body, call modes and concrete bindings at an Eva lookup is an open OCaml obligation. |
| `[Memory M]` and `a : AllocatorAgreement M` | Model interfaces with laws proved for `FunMem` and `FunMem.allocatorAgreement`. Actual agreement on a producing and current pair is part of replay compatibility. |
| `entry.Sound a` | Proved in Lean by `sound_of_producer` under nonemptiness, producer soundness, footprint coverage and key coverage. The corresponding Eva obligations and relied-on producer contract are listed in [entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage). |
| Weak `filter` soundness on `cur` and the stored key | Local domain-law premise. Proved for `valueDom`. The cvalue argument is under [filter sound](reuse-operation.md#filter-sound-for-cvalue). Each admitted domain owes this law at its projection. |
| `d.ExactOn entry.key entry.input` | Local stored-side domain-law premise. The product lemma derives it from composition of the component decompositions, a closed stored key, `Combinable` and a nonempty stored concretisation. No current-side closure is used. The Eva obligations are under [Matching](matching.md#closure-in-the-stored-input-suffices-for-the-match) and [cvalue exactness](reuse-operation.md#filter-exact-on-the-stored-input-for-cvalue). |
| Inclusion of the filtered current input in the filtered stored input | OCaml obligation. Equality implies inclusion for a common interpretation of filtered states. The equality check is exercised in the [operation record](reuse-operation.md#the-match-by-equality). The argument that those interpreted input states and environments apply to each admitted lookup is open. |
| `entry.ReplayCompatible a cur` | OCaml obligation, open. The matched lookup must supply the joint witness above. Equal contents on `K` give liveness there. For other write targets, justify liveness with the same witness. Justify matching the allocation state that determines the identities of new concrete locals. Refusing allocated bases and enlarging the key are separate checks. |
| `∀ o, d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o)` | Local domain-law premise. Proved for `valueDom` by its global law. [The restricted cvalue argument](reuse-operation.md#reuse-sound-for-cvalue) requires the exit binding condition. Its applicability to actual admitted exits, including lifetime changes and domain products where applicable, is an OCaml obligation. |
| `∀ m, d.γ cur m → entry.NoFrameRewrite m` | OCaml obligation. For the recorded targets, the produced-entry supplied lookup checks a stronger condition on the input map. Coverage of actual sweeps remains a premise. See [sweep admission](frame.md#admission-condition-for-sweeps-of-own-locals). |
| `d.γ cur m`, `entry.Matches a m`, `entry.NoFrameRewrite m` in the common hit lemma | Local member premises. The projected theorem obtains `Matches` via the match lemma and replay compatibility. The frame premise comes from admission for this memory. The pointwise theorem needs only membership in the current concretisation. That membership supplies nonemptiness whenever the theorem is applied. |

In `exit_preserves_absence`, the subject, state, block, event list,
outcome and output are model parameters. Its local premises are absence
of the input binding and the normal-exit prefix. The proof tracks a
fresh live block in a call or lexical scope frame until that frame
releases it. A fault need not unwind its frames and is outside this
lemma's conclusion. In `exit_frame_iff`, the entry and memories,
trace and outcome are model parameters. Its local premises are
`entry.Covers m` from entry soundness and the normal-exit prefix.
`matches_of_projected` uses the filter, exactness, inclusion,
compatibility and membership premises listed above.
`replayCompatible_iff_matches` uses the same model parameters and the
three local projection premises from that table. The fields of
`HitObservations` take the normal Exit, reached label, violation,
or assertion visit of the indicated execution as local premises. The
validity field also takes the absence of a possible assertion
violation from the entry. `ReplayCompatible`, `NoFrameRewrite`,
`ReuseSoundAt` and `ReuseSound` are definitions whose arguments are
model parameters. Their implications range over covered members,
producing witnesses, traces, or cell values as given in the definitions.

**Does `reuse` need an exactness law?** The theorem needs just
`ReuseSoundAt`: every actual exit in the proof is one of the
combinations it must cover. An operation that covers additional
memories can satisfy the theorem. Equality with fresh analysis and
structural overlay identities are different claims.

## Value-domain instance and checked cases

**Kind.** Proved in Lean.

**Hypotheses of `valueDom_hit`.** The entry and current state are model
parameters. Soundness, filtered inclusion and no frame rewrite have
the meanings and kinds above. The model proves the value domain's
filter and reuse laws and supplies the exactness proof from its
`relate` law, the closed stored key, `FunMem.combinable` and
`Sound.nonempty`. Two value-domain admission conditions replace
`ReplayCompatible`: for each current member, every constrained stored
block off the key fits below the current next identifier, and each
such block in the write bound is live in the current memory. These are
local premises of the model instance, proved for its example. The
constructed witness takes the stored constrained cells off the key,
all other cells from the current memory, and the current next
identifier. The key witness ensures the stored constraints on the key.
The two checks are also necessary for a replay witness on this
domain, since every stored constrained block is live and a live
block has already been issued. The checks are about `valueDom` and
`FunMem`. Eva still owes the corresponding open lookup obligation.

**Checked cases.** The fixture definitions are closed model data. The
checks are closed propositions, with no external premises.

| Check | Observed model behavior |
|---|---|
| `value_hit_distinct_member` | The producer has `x=3, p=1, keep=4`. The member has `x=5, p=1, keep=9`, outside the stored input. For `assert(p); x = 7;`, the producer satisfies every construction premise, the member reaches the valid assertion, and its exit has `x=7, keep=9`. The unmodified stored exit excludes that memory. |
| `hit_needs_write_liveness` | The key is still `{p}` and the allocator is unchanged. The stored entry overwrites a live `x`; the current `x` was released. The hit would miss an actual invalid-access fault at label 3. |
| `hit_needs_allocator_agreement` | The two value-domain inputs agree on the projection, and `x` is live in both memories. The stored input constrains block 2, which no memory with the current next identifier 2 can bind. |
| `allocator_mismatch_loses_exit` | With no ordinary writes and the same projection, a lexical scope that returns the local's escaped address produces `escaped 3` in the stored run and `escaped 2` in the current run. The latter outcome has no stored exit, and the exact overlay excludes it. |
| `hit_needs_no_frame_rewrite` | The sweep entry has a sound producer and the projected match supplies the full replay witness. The current holder outside `W_exit` changes from `ptr 2` to `escaped 2`. The exact unchanged overlay excludes the actual exit. |
| `hit_observations_do_not_imply_match` | Adding the frame block to the key preserves entry soundness. The entry then requires `keep=4` on that key and rejects the member with `keep=9`, even though all of its `HitObservations` hold. Checking observations at one member cannot justify the lookup rule. |
| `hit_frame_absent_bindings` | A released binding stays absent at exit. A separate unissued identifier is live inside the scope and absent again after the sweep. |

## Side-table obligations for skipped work

**Kind.** OCaml obligations, open. Lean states four separate predicates.
[Side-table inventory and classifications](https://github.com/nyandrianinamamy/frama-c/issues/25#issuecomment-6976816913)
is the source of the classes. The four obligations are assumed to
cover every table of the inventory. Exhaustiveness has not been shown.

Each predicate is instantiated for one run and one class of table
access. Its types and functions are model parameters. The relations
`reads`, `writes`, `producerAccess`, and `hitAccess` must include
all corresponding work skipped by the entry, including transitive
nested work and repeated observations. That coverage is an open OCaml
obligation. `KeyedRead` constrains reported reads only. The checked
example reports the direct read and satisfies `KeyedRead`, even though
the unreported nested read differs from the saved observation.
`admitted` identifies accepted lookups and `stored`
identifies constructed entries. A table with no position dimension
uses a single position. An overwrite is unsupported unless it has
a separate soundness argument. The proof of hit observations concerns
concrete model executions. Application to Eva must separately satisfy
these contracts for shared observations and contributions.

| Contract | Eva symbols and open evidence |
|---|---|
| `KeyedRead` | `Widen.getWidenHints` records the entry generation. A produced entry's supplied lookup compares it before acceptance. The reader replays check the generation with and without discovery. The replacement cache must retain the check. [Dynamic widening hints](collector-effects.md#dynamic-widening-hints). |
| `FixedRead` | `Cil` AST queries, effective contracts in `Annotations.funspec`, selected builtin and static configuration must be invariant at every time in the run for each fixed observation. The classification is supported by source inspection of the inventory and [body-access record](body-access.md#side-tables-and-recorded-joins). The invariant for every admitted observation and the audit of helpers and memos remain open. |
| `RecordedWrite` | `Iterator.record_fireable`, `Iterator.Make_Dataflow.merge_results`, `Function_calls.register_call`, `Alarmset.register_alarm`, `Transfer_logic.emit_status` and `Engine.Store.register_state` are relevant writers. The collector fixture asserts recorded classes. Each table owes an interpretation of its values, operand coverage for the join, and a replay argument at the hit's table index. The result must cover the fresh and existing observations there and preserve coverage at the other positions. These OCaml obligations remain open. #47 and #48 owe confirmed hit checks for Safety and Reach. A position-independent join can be replayed once when repetition adds nothing. A callstack-indexed effect must be delivered for each current position. |
| `UnsupportedAccess` | `Body_access.unknown_access`, `Body_access.read_message_history`, and `Cache_producer.produce` report or enforce refusals at instrumented storage paths. The fixtures exercise temporary origins, ordered effects and unclassified callbacks. The collector propagates the named effects from fresh nested work. Coverage of the whole inventory and lookup in the replacement cache remain open. [Ordered and opaque effects](collector-effects.md#ordered-and-opaque-effects). |

In `RecordedWrite`, `represents` gives the observations accounted for
by a table value. `Covers represents value contribution` is inclusion of
the contribution's observations in those of the value. The join covers
both operands. At the current position, the result of joining the saved
payload with the prior cell must cover both the skipped computation's
fresh contribution and the prior cell. A fresh observation can already
be present in that cell. At other positions, the represented
observations are the same before and after replay.

```lean
def KeyedRead {Hit Read Value : Type} (admitted : Hit → Prop)
    (reads : Hit → Read → Prop) (saved lookup : Hit → Read → Value) : Prop :=
  ∀ hit, admitted hit → ∀ read, reads hit read → saved hit read = lookup hit read

def FixedRead {Time Read Value : Type} (observe : Time → Read → Value) : Prop :=
  ∀ t₁ t₂ read, observe t₁ read = observe t₂ read

def Covers {Value Observation : Type} (represents : Value → Observation → Prop)
    (value contribution : Value) : Prop :=
  ∀ o, represents contribution o → represents value o

def RecordedWrite {Hit Position Value Observation : Type} (admitted writes : Hit → Prop)
    (position : Hit → Position) (fresh saved : Hit → Value)
    (before after : Hit → Position → Value) (join : Value → Value → Value)
    (represents : Value → Observation → Prop) : Prop :=
  (∀ x y z, join (join x y) z = join x (join y z)) ∧
  (∀ x y, join x y = join y x) ∧ (∀ x, join x x = x) ∧
  (∀ x y, Covers represents (join x y) x ∧ Covers represents (join x y) y) ∧
  ∀ hit, admitted hit → writes hit →
    after hit (position hit) = join (before hit (position hit)) (saved hit) ∧
    Covers represents (after hit (position hit)) (before hit (position hit)) ∧
    Covers represents (after hit (position hit)) (fresh hit) ∧
    ∀ p, p ≠ position hit → ∀ o, represents (after hit p) o ↔ represents (before hit p) o

def UnsupportedAccess {Entry Hit Access : Type} (stored : Entry → Prop)
    (admitted : Hit → Prop) (producerAccess : Entry → Access → Prop)
    (hitAccess : Hit → Access → Prop) (unsupported : Access → Prop) : Prop :=
  (∀ entry access, producerAccess entry access → unsupported access → ¬ stored entry) ∧
  (∀ hit access, hitAccess hit access → unsupported access → ¬ admitted hit)
```

`FixedRead.agrees_on_reads` derives the earlier, read-relative
agreement from run-wide invariance. Its types, observation and read
relation are model parameters. Its local premises are invariance and
the two reported reads. The two-time fixture has a Boolean flag that
changes and is reported only at the first time. It satisfies read-relative
agreement and fails run-wide invariance.

The checks exercise an actual keyed read, a changed keyed read, fixed
invariance, replay at the current position and refusal of unsupported
work. For a reached bit, `true` represents that the site was reached.
OR preserves a reached bit already in the table even with a false
payload, and AND loses it. The other negative cases cover a fresh
observation absent from both the payload and the table, erasure at an
unrelated populated position, and storage after an unsupported producer
access. Each of the four mutations compiled the weakened definition
and made its corresponding check fail to compile. The unmodified
definition and checks compiled in the scratch control.

Eva's [dynamic widening generation](collector-effects.md#dynamic-widening-hints)
is a `KeyedRead`. Discovery, ordered and opaque effects and unclassified
emission-history reads are `UnsupportedAccess` in
[the collector](collector-effects.md#ordered-and-opaque-effects).

## Evidence and printed declarations

Tree of `lean/` `c87015b3742b0acb20e9ee1a0e51afa3648bf218` at
commit `0acc22c6077e0c7145602cb2d82972abc51c1971`.
On 2026-11-19, `cd lean && lake build --wfail` exited 0 in the rebased
worktree using Lean 4.28.0 (`7e01a1bf5c70`). CI:
[run 44436454539](https://github.com/nyandrianinamamy/frama-c/actions/runs/44436454539)
succeeded on this tree. No OCaml check
was executed for this entry.

Replay the statements and axiom reports with the build above. The
declarations below are printed by
[`Checks/Axioms.lean`](../../../lean/Checks/Axioms.lean).
The build also runs `#check_axioms` on each declaration.

### Model declarations

```text
@Domain.ReuseSoundAt : {M : Type} → [Memory M] → (d : Domain M) → BlockSet → d.State → d.State → Prop
'ReuseModel.Domain.ReuseSoundAt' does not depend on any axioms
```

```text
@Domain.ReuseSound : {M : Type} → [Memory M] → Domain M → Prop
'ReuseModel.Domain.ReuseSound' does not depend on any axioms
```

```text
@exit_preserves_absence : ∀ {M : Type} [inst : Memory M] {t : Subject} {σ : State M} {b : Block},
  Memory.load σ.mem b = none →
    ∀ {evs : List Event} {o : Outcome} {out : M}, Prefix t σ evs (Config.done o out) → Memory.load out b = none
'ReuseModel.exit_preserves_absence' depends on axioms: [propext, Quot.sound]
```

```text
@CacheEntry.ReplayCompatible : {M : Type} →
  [inst : Memory M] → {d : Domain M} → CacheEntry d → AllocatorAgreement M → d.State → Prop
'ReuseModel.CacheEntry.ReplayCompatible' depends on axioms: [propext]
```

```text
@CacheEntry.matches_of_projected : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d}
  {a : AllocatorAgreement M} {cur : d.State},
  (∀ (m : M), d.γ cur m → d.γ (d.filter entry.key cur) m) →
    d.ExactOn entry.key entry.input →
      (∀ (m : M), d.γ (d.filter entry.key cur) m → d.γ (d.filter entry.key entry.input) m) →
        entry.ReplayCompatible a cur → ∀ {m : M}, d.γ cur m → entry.Matches a m
'ReuseModel.CacheEntry.matches_of_projected' depends on axioms: [propext]
```

```text
@CacheEntry.replayCompatible_iff_matches : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d}
  {a : AllocatorAgreement M} {cur : d.State},
  (∀ (m : M), d.γ cur m → d.γ (d.filter entry.key cur) m) →
    d.ExactOn entry.key entry.input →
      (∀ (m : M), d.γ (d.filter entry.key cur) m → d.γ (d.filter entry.key entry.input) m) →
        (entry.ReplayCompatible a cur ↔ ∀ (m : M), d.γ cur m → entry.Matches a m)
'ReuseModel.CacheEntry.replayCompatible_iff_matches' depends on axioms: [propext]
```

```text
@CacheEntry.NoFrameRewrite : {M : Type} → [Memory M] → {d : Domain M} → CacheEntry d → M → Prop
'ReuseModel.CacheEntry.NoFrameRewrite' depends on axioms: [propext]
```

```text
@CacheEntry.exit_frame_iff : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {m out : M},
  entry.Covers m →
    ∀ {evs : List Event} {o : Outcome},
      Prefix entry.subject { env := entry.env, mem := m } evs (Config.done o out) →
        (AgreeOff entry.footprint.exitWrites out m ↔
          ∀ (b : Block),
            ¬b ∈ entry.footprint.exitWrites →
              ∀ (target : Block), target ∈ sweepTargets evs → Memory.load m b ≠ some (Value.ptr target))
'ReuseModel.CacheEntry.exit_frame_iff' depends on axioms: [propext, Quot.sound]
```

```text
@CacheEntry.HitObservations : {M : Type} → [Memory M] → {d : Domain M} → CacheEntry d → d.State → M → Prop
'ReuseModel.CacheEntry.HitObservations' depends on axioms: [propext]
```

```text
@CacheEntry.HitObservations.exit : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {cur : d.State}
  {m : M},
  entry.HitObservations cur m →
    ∀ (o : Outcome) (out : M),
      Exit entry.subject { env := entry.env, mem := m } o out →
        d.γ (d.reuse entry.footprint.exitWrites cur (entry.exit o)) out ∧ AgreeOff entry.footprint.exitWrites out m
'ReuseModel.CacheEntry.HitObservations.exit' depends on axioms: [propext]
```

```text
@CacheEntry.HitObservations.reach : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {cur : d.State}
  {m : M},
  entry.HitObservations cur m → ∀ (l : Label), Reach entry.subject { env := entry.env, mem := m } l → entry.reached l
'ReuseModel.CacheEntry.HitObservations.reach' depends on axioms: [propext]
```

```text
@CacheEntry.HitObservations.safety : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d}
  {cur : d.State} {m : M},
  entry.HitObservations cur m →
    ∀ (v : Violation), Unsafe entry.subject { env := entry.env, mem := m } v → entry.violations v
'ReuseModel.CacheEntry.HitObservations.safety' depends on axioms: [propext]
```

```text
@CacheEntry.HitObservations.valid : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {cur : d.State}
  {m : M},
  entry.HitObservations cur m →
    ∀ (l : Label) (e : Expr) (k : Cont) (env : Env) (atVisit : M) (evs : List Event),
      ¬entry.violations (Violation.assertion l) →
        Prefix entry.subject { env := entry.env, mem := m } evs (Config.run (Stmt.assert l e) k env atVisit) →
          assertionHolds entry.subject.prog env atVisit e = true
'ReuseModel.CacheEntry.HitObservations.valid' depends on axioms: [propext]
```

```text
@CacheEntry.hit_of_matches : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d}
  {a : AllocatorAgreement M} {cur : d.State},
  entry.Sound a →
    (∀ (o : Outcome), d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o)) →
      ∀ {m : M}, d.γ cur m → entry.Matches a m → entry.NoFrameRewrite m → entry.HitObservations cur m
'ReuseModel.CacheEntry.hit_of_matches' depends on axioms: [propext, Quot.sound]
```

```text
@CacheEntry.hit : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {a : AllocatorAgreement M}
  {cur : d.State},
  entry.Sound a →
    (∀ (m : M), d.γ cur m → d.γ (d.filter entry.key cur) m) →
      d.ExactOn entry.key entry.input →
        (∀ (m : M), d.γ (d.filter entry.key cur) m → d.γ (d.filter entry.key entry.input) m) →
          entry.ReplayCompatible a cur →
            (∀ (o : Outcome), d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o)) →
              (∀ (m : M), d.γ cur m → entry.NoFrameRewrite m) → ∀ (m : M), d.γ cur m → entry.HitObservations cur m
'ReuseModel.CacheEntry.hit' depends on axioms: [propext, Quot.sound]
```

### Side-table declarations

```text
@KeyedRead : {Hit Read Value : Type} →
  (Hit → Prop) → (Hit → Read → Prop) → (Hit → Read → Value) → (Hit → Read → Value) → Prop
'ReuseModel.SideTables.KeyedRead' does not depend on any axioms
```

```text
@FixedRead : {Time Read Value : Type} → (Time → Read → Value) → Prop
'ReuseModel.SideTables.FixedRead' does not depend on any axioms
```

```text
@FixedRead.agrees_on_reads : ∀ {Time Read Value : Type} {observe : Time → Read → Value},
  FixedRead observe →
    ∀ (reads : Time → Read → Prop) (t₁ t₂ : Time) (read : Read),
      reads t₁ read → reads t₂ read → observe t₁ read = observe t₂ read
'ReuseModel.SideTables.FixedRead.agrees_on_reads' does not depend on any axioms
```

```text
@Covers : {Value Observation : Type} → (Value → Observation → Prop) → Value → Value → Prop
'ReuseModel.SideTables.Covers' does not depend on any axioms
```

```text
@RecordedWrite : {Hit Position Value Observation : Type} →
  (Hit → Prop) →
    (Hit → Prop) →
      (Hit → Position) →
        (Hit → Value) →
          (Hit → Value) →
            (Hit → Position → Value) →
              (Hit → Position → Value) → (Value → Value → Value) → (Value → Observation → Prop) → Prop
'ReuseModel.SideTables.RecordedWrite' does not depend on any axioms
```

```text
@UnsupportedAccess : {Entry Hit Access : Type} →
  (Entry → Prop) → (Hit → Prop) → (Entry → Access → Prop) → (Hit → Access → Prop) → (Access → Prop) → Prop
'ReuseModel.SideTables.UnsupportedAccess' does not depend on any axioms
```

### Value-domain instance and checks

```text
@valueDom_hit : ∀ {entry : CacheEntry (valueDom FunMem)} {cur : (valueDom FunMem).State},
  entry.Sound FunMem.allocatorAgreement →
    (∀ (m : FunMem),
        (valueDom FunMem).γ ((valueDom FunMem).filter entry.key cur) m →
          (valueDom FunMem).γ ((valueDom FunMem).filter entry.key entry.input) m) →
      (∀ (m : FunMem),
          (valueDom FunMem).γ cur m →
            ∀ (p : Block × List Value), List.Mem p entry.input → ¬p.fst ∈ entry.key → p.fst < m.next) →
        (∀ (m : FunMem),
            (valueDom FunMem).γ cur m →
              ∀ (p : Block × List Value),
                List.Mem p entry.input → ¬p.fst ∈ entry.key → p.fst ∈ entry.footprint.writes → Live m p.fst) →
          (∀ (m : FunMem), (valueDom FunMem).γ cur m → entry.NoFrameRewrite m) →
            ∀ (m : FunMem), (valueDom FunMem).γ cur m → entry.HitObservations cur m
'Checks.valueDom_hit' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hitStmt : Stmt
'Checks.hitStmt' does not depend on any axioms
```

```text
Checks.hitSubject : Subject
'Checks.hitSubject' depends on axioms: [propext]
```

```text
Checks.hitEntry : CacheEntry (valueDom FunMem)
'Checks.hitEntry' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hitCurrent : (valueDom FunMem).State
'Checks.hitCurrent' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hitProducer : FunMem
'Checks.hitProducer' depends on axioms: [propext]
```

```text
Checks.hitMember : FunMem
'Checks.hitMember' depends on axioms: [propext]
```

```text
Checks.hitOutput : FunMem
'Checks.hitOutput' depends on axioms: [propext]
```

```text
Checks.value_hit_distinct_member :
  (valueDom FunMem).γ hitCurrent hitMember ∧
    ¬(valueDom FunMem).γ hitEntry.input hitMember ∧
      hitEntry.HitObservations hitCurrent hitMember ∧
        Exit hitSubject { env := noLocals, mem := hitMember } Outcome.completed hitOutput ∧
          (valueDom FunMem).γ ((valueDom FunMem).reuse [0] hitCurrent (hitEntry.exit Outcome.completed)) hitOutput ∧
            ¬(valueDom FunMem).γ (hitEntry.exit Outcome.completed) hitOutput ∧
              Memory.load hitOutput 0 = some (Value.int 7) ∧
                Memory.load hitOutput 2 = some (Value.int 9) ∧
                  hitEntry.reached 2 ∧ assertionHolds loadProg noLocals hitMember (Expr.var "p") = true
'Checks.value_hit_distinct_member' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hit_observations_do_not_imply_match :
  have larger :=
    have __src := hitEntry;
    { subject := __src.subject, env := __src.env, input := __src.input, key := [1, 2], footprint := __src.footprint,
      exit := __src.exit, violations := __src.violations, reached := __src.reached };
  larger.Sound FunMem.allocatorAgreement ∧
    (valueDom FunMem).γ hitCurrent hitMember ∧
      ¬larger.Matches FunMem.allocatorAgreement hitMember ∧ larger.HitObservations hitCurrent hitMember
'Checks.hit_observations_do_not_imply_match' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hit_needs_write_liveness :
  have dead := Memory.release hitMember 0;
  have cur := [(1, [Value.int 1]), (2, [Value.int 9])];
  hitEntry.Sound FunMem.allocatorAgreement ∧
    (valueDom FunMem).filter hitEntry.key cur = (valueDom FunMem).filter hitEntry.key hitEntry.input ∧
      (valueDom FunMem).γ cur dead ∧
        AgreeOn hitEntry.key dead hitProducer ∧
          FunMem.allocatorAgreement.rel hitProducer dead ∧
            ¬hitEntry.ReplayCompatible FunMem.allocatorAgreement cur ∧
              (∀ (m : FunMem), (valueDom FunMem).γ cur m → hitEntry.NoFrameRewrite m) ∧
                AlarmRaised hitSubject { env := noLocals, mem := dead } 3 Alarm.invalidAccess ∧
                  ¬hitEntry.HitObservations cur dead
'Checks.hit_needs_write_liveness' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hit_needs_allocator_agreement :
  have short := memOf [Value.int 5, Value.int 1];
  have cur := [(0, [Value.int 5]), (1, [Value.int 1])];
  hitEntry.Sound FunMem.allocatorAgreement ∧
    (valueDom FunMem).filter hitEntry.key cur = (valueDom FunMem).filter hitEntry.key hitEntry.input ∧
      (valueDom FunMem).γ cur short ∧
        AgreeOn hitEntry.key short hitProducer ∧
          (∀ (b : Block),
              b ∈ hitEntry.footprint.writes → (Memory.load hitProducer b).isSome = (Memory.load short b).isSome) ∧
            hitEntry.NoFrameRewrite short ∧ ¬hitEntry.ReplayCompatible FunMem.allocatorAgreement cur
'Checks.hit_needs_allocator_agreement' depends on axioms: [propext, Quot.sound]
```

```text
Checks.allocator_mismatch_loses_exit :
  allocatorEntry.Sound FunMem.allocatorAgreement ∧
    projectedPredicates.FilterSound ∧
      projectedPredicates.ExactOn allocatorEntry.key allocatorEntry.input ∧
        (∀ (m : FunMem),
            projectedPredicates.γ (projectedPredicates.filter allocatorEntry.key allocCur) m →
              projectedPredicates.γ (projectedPredicates.filter allocatorEntry.key allocatorEntry.input) m) ∧
          projectedPredicates.ReuseSound ∧
            (∀ (m : FunMem), projectedPredicates.γ allocCur m → allocatorEntry.NoFrameRewrite m) ∧
              ¬allocatorEntry.ReplayCompatible FunMem.allocatorAgreement allocCur ∧
                ¬allocatorEntry.HitObservations allocCur shortState.mem
'Checks.allocator_mismatch_loses_exit' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hit_needs_no_frame_rewrite :
  projectedSweep.Sound FunMem.allocatorAgreement ∧
    projectedPredicates.FilterSound ∧
      projectedPredicates.ExactOn projectedSweep.key projectedSweep.input ∧
        (∀ (m : FunMem),
            projectedPredicates.γ (projectedPredicates.filter projectedSweep.key sweepCur) m →
              projectedPredicates.γ (projectedPredicates.filter projectedSweep.key projectedSweep.input) m) ∧
          projectedSweep.ReplayCompatible FunMem.allocatorAgreement sweepCur ∧
            projectedPredicates.ReuseSound ∧
              ¬projectedSweep.NoFrameRewrite futurePointerInput.mem ∧
                ¬projectedSweep.HitObservations sweepCur futurePointerInput.mem
'Checks.hit_needs_no_frame_rewrite' depends on axioms: [propext, Quot.sound]
```

```text
Checks.hit_frame_absent_bindings :
  have σ := { env := noLocals, mem := Memory.release sweepInput.mem 1 };
  Memory.load σ.mem 1 = none ∧
    Memory.load σ.mem 2 = none ∧
      Memory.load (sweepRun σ 2).snd.mem 2 = some (Value.int 9) ∧
        Memory.load (sweepRun σ 7).snd.mem 1 = none ∧ Memory.load (sweepRun σ 7).snd.mem 2 = none
'Checks.hit_frame_absent_bindings' depends on axioms: [propext, Quot.sound]
```

```text
Checks.side_table_contracts :
  (KeyedRead (fun x => True) (fun x x_1 => True) (fun x x_1 => true) fun x x_1 => true) ∧
    (¬KeyedRead (fun x => True) (fun x x_1 => True) (fun x x_1 => true) fun x x_1 => false) ∧
      (FixedRead fun x x_1 => true) ∧
        (RecordedWrite (fun x => True) (fun x => True) (fun x => true) (fun x => true) (fun x => true)
            (fun x x_1 => false) (fun x p => p) or fun v x => v = true) ∧
          (¬RecordedWrite (fun x => True) (fun x => True) (fun x => true) (fun x => true) (fun x => true)
                (fun x x_1 => false) (fun x p => !p) or fun v x => v = true) ∧
            (UnsupportedAccess (fun x => False) (fun x => False) (fun x x_1 => True) (fun x x_1 => True) fun x =>
                True) ∧
              ¬UnsupportedAccess (fun x => False) (fun x => True) (fun x x_1 => True) (fun x x_1 => True) fun x => True
'Checks.side_table_contracts' depends on axioms: [propext, Quot.sound]
```

```text
Checks.fixed_read_needs_run_invariance : (∀ (t₁ t₂ : Bool), t₁ = false → t₂ = false → t₁ = t₂) ∧ ¬FixedRead fun t x => t
'Checks.fixed_read_needs_run_invariance' does not depend on any axioms
```

```text
Checks.keyed_read_can_miss_nested_read :
  have reads := fun x nested => nested = false;
  have saved := fun x x_1 => false;
  have lookup := fun x nested => nested;
  KeyedRead (fun x => True) reads saved lookup ∧ ¬reads () true ∧ saved () true ≠ lookup () true
'Checks.keyed_read_can_miss_nested_read' does not depend on any axioms
```

```text
Checks.recorded_write_preserves_current_reach :
  (RecordedWrite (fun x => True) (fun x => True) (fun x => ()) (fun x => true) (fun x => false) (fun x x_1 => true)
      (fun x x_1 => true) or fun v x => v = true) ∧
    ¬RecordedWrite (fun x => True) (fun x => True) (fun x => ()) (fun x => true) (fun x => false) (fun x x_1 => true)
        (fun x x_1 => false) and fun v x => v = true
'Checks.recorded_write_preserves_current_reach' depends on axioms: [propext]
```

```text
Checks.recorded_write_needs_fresh_coverage :
  ¬RecordedWrite (fun x => True) (fun x => True) (fun x => ()) (fun x => true) (fun x => false) (fun x x_1 => false)
      (fun x x_1 => false) or fun v x => v = true
'Checks.recorded_write_needs_fresh_coverage' does not depend on any axioms
```

```text
Checks.recorded_write_preserves_other_positions :
  ¬RecordedWrite (fun x => True) (fun x => True) (fun x => true) (fun x => true) (fun x => true) (fun x p => !p)
      (fun x p => p) or fun v x => v = true
'Checks.recorded_write_preserves_other_positions' does not depend on any axioms
```

```text
Checks.unsupported_producer_prevents_storage :
  ¬UnsupportedAccess (fun x => True) (fun x => False) (fun x x_1 => True) (fun x x_1 => False) fun x => True
'Checks.unsupported_producer_prevents_storage' does not depend on any axioms
```

```text
Checks.projectedPredicates : Domain FunMem
'Checks.projectedPredicates' depends on axioms: [propext]
```

```text
Checks.allocatorEntry : CacheEntry projectedPredicates
'Checks.allocatorEntry' depends on axioms: [propext]
```

```text
Checks.shortState : State FunMem
'Checks.shortState' depends on axioms: [propext]
```

```text
Checks.allocCur : projectedPredicates.State
'Checks.allocCur' depends on axioms: [propext]
```

```text
Checks.projectedSweep : CacheEntry projectedPredicates
'Checks.projectedSweep' depends on axioms: [propext]
```

```text
Checks.sweepCur : projectedPredicates.State
'Checks.sweepCur' depends on axioms: [propext]
```

## Follow-on Lean work

- #40: [State queries on the callstack of a hit](query.md) proves the
  joined answers of the hit log sound at each visit of a matching member
  of any line that applies, with
  the joint witness as a premise that a projected or whole-product hit
  supplies. Publishing a per-position Inner contribution through a
  recorded join, rather than answering at query time, is not modelled:
  it also requires coverage of fresh visits and of existing observations
  there, with other positions preserved. A successful query example alone
  does not validate admission.
  [Public Inner reconstruction](https://github.com/nyandrianinamamy/frama-c/issues/40).

## Follow-on Eva work

- #57 owes the [whole-product admission argument and checks](whole-product.md#whole-product-admission-in-eva),
  including the common namespace, the comparison of every active
  component, and per-domain replay and refusal evidence.
- #66 must audit those open checks alongside the existing producer,
  frame, reuse and side-table obligations. The
  [relational precision example](whole-product.md#projection-without-current-side-closure-can-lose-a-relation)
  is evidence about the Lean model.
- #47 must define which alarm, status and red-context observations each
  table value covers. Show that the kernel's combination covers both
  operands, that actual hit replay covers the fresh and prior contributions
  at the current position, and that other positions retain coverage.
  Preconditions of the callee still run outside the entry.
  [Safety replay](https://github.com/nyandrianinamamy/frama-c/issues/47).
- #48 owes the same argument for reached statements, caller sites, guards,
  enabled zones and holder sets. True represents reach, so its join is OR.
  Per-position replay must preserve prior contributions on that callstack
  and preserve coverage on other callstacks. The caller still runs the
  outer finalization. Both tickets owe cases with a confirmed hit and
  must account for nested work and unsupported producer accesses.
  [Reach replay](https://github.com/nyandrianinamamy/frama-c/issues/48).
