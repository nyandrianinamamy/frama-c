# Shared Inner

## Coverage of matching visits on the key

**Kind.** Proved in Lean.

**Claim.** For every concrete member of the key group satisfying
`entry.Matches a m`, and every before-statement visit of that member, the
shared state at the label has a concrete representative agreeing with
the visited memory on every block of `entry.key` issued in the matching
member's entry memory. The representative may vary between visits of one
label.

A body local read after its creation can belong to the lookup key, where
it matches by absence at entry. The model issues a fresh identifier on
each entry into the scope. Eva uses one base per variable. Identity
across lifetimes is open for sweeps in #44. A consumer of shared Inner
must exclude key blocks created after entry from this guarantee and
justify those answers separately. [Spec note from #46](https://github.com/nyandrianinamamy/frama-c/issues/32).

**Scope.** Whole blocks, before-statement visits of a `Subject`, including
visits on a finite prefix before a fault or in a nonreturning call.
`InnerSound` expresses the producer's obligation using key projection
of the concretisation. A full saved state covering a producing visit can
use that visit's memory as the representative. This covers a saved state
joined over all visits at one label. The model assumes the coverage of
that state and does not prescribe a join operation.

**Declarations.** [Entry](../../../lean/ReuseModel/Entry.lean).
`AgreeOn K w m` compares `Memory.load` for each member of `K`.

**Statements and axiom output.**

```lean
@CacheEntry.InnerSound : {M : Type} → {d : Domain M} → [Memory M] → CacheEntry d → (Label → d.State) → Prop
'ReuseModel.CacheEntry.InnerSound' depends on axioms: [propext]

@CacheEntry.shared_inner : ∀ {M : Type} {d : Domain M} [inst : Memory M] {entry : CacheEntry d}
  {a : AllocatorAgreement M} {inner : Label → d.State},
  entry.InnerSound inner →
    entry.Coverage →
      entry.KeyCovers →
        ∀ {m : M},
          entry.Matches a m →
            ∀ {l : Label} {env : Env} {atVisit : M},
              Visit entry.subject { env := entry.env, mem := m } l env atVisit →
                ∃ represented,
                  d.γ (inner l) represented ∧
                    ∀ (b : Block), b ∈ entry.key → Memory.Issued m b → Memory.load represented b = Memory.load atVisit b
'ReuseModel.CacheEntry.shared_inner' depends on axioms: [propext, Quot.sound]
```

**Hypotheses.**

| Hypothesis or parameter | Kind and scope |
| --- | --- |
| `[Memory M]` | Model interface, proved in Lean for `FunMem`. Includes the lexical sweep laws in [Frame](frame.md#frame-lemma-with-lexical-sweeps). |
| `d : Domain M` | Model parameter. The proof uses the domain's concretisation. The domain laws for deriving the projected match have their own [record](domain-laws.md#the-laws-in-the-model). |
| `entry : CacheEntry d`, `inner : Label → d.State` | Model parameters. The entry supplies the common program, subject, initial bindings, key and footprint. The label-indexed family supplies the producer's saved states. |
| `a : AllocatorAgreement M` | Model laws, proved in Lean for `FunMem.allocatorAgreement`. Includes reflexivity and stability under paired sweeps. |
| `entry.InnerSound inner` | Relied on from Eva for the stored states as a producer property. Coverage of every producing visit on the key is the hypothesis. The correspondence for the referenced state is open below. |
| `entry.Coverage` | OCaml obligation. Only coverage of all reads and attempted writes on producing prefixes is used here. The bounds on normal exits also belong to the reused predicate. See [entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage). |
| `entry.KeyCovers` | OCaml obligation. Only inclusion of the reads in the key is used here. The key also covers possible exit writes other than certain overwrites under the reused predicate. |
| `m : M`, `l : Label`, `env : Env`, `atVisit : M` | Model parameters selecting a concrete member and a visit. |
| `entry.Matches a m` | OCaml obligation for an admitted match. One stored witness must agree on key contents, liveness of write targets and allocator state with the same entry bindings. A projected match alone gives key agreement. |
| `b ∈ entry.key` and `Memory.Issued m b` | Local model premises selecting the blocks covered by the conclusion. Issuance is tested in the matching memory at entry. |
| `Visit entry.subject { env := entry.env, mem := m } l env atVisit` | Local model premise. A finite prefix starts at the member input and reaches the indicated before-statement configuration. |

**Depends on.** [Finite-prefix correspondence](entry.md#finite-prefix-correspondence).
Replay aligns the control configuration and propagates agreement on the key
after each step, including lexical sweeps. The producing visit then supplies
a representative for the producing memory. The conclusion uses their
agreement on the entry-issued key blocks.

**Evidence.** Tree of `lean/` `baaacef349ee92e373475ca88b596619282b3ed2` at
commit `fa1175a44de40098071cb2ada6674a2fa875876f`. `cd lean && lake build --wfail`
completed with exit status 0 using the pinned Lean 4.28.0 toolchain.
CI is pending.

**Checked cases.** For `i = 0; while (i < 2) { L: i++; }`, the producer
starts from `(i, other) = (9, 7)` and the matching member starts from
`(9, 8)`, both with the same allocation state. The key is `{i}`. The
fixture checks the producer, footprint and stored Inner premises using all
12 finite-run positions up to completion. The shared state at label 4
admits both 0 and 1 at the member's visits. A state containing just the
first value at label 4 accepts the first visit there and fails the
producer premise at the second. The validated state is used at every
other label. Even the two-visit state cannot cover the member's `other`
value.

For `{ int t = 9; L: return t; }`, the checked read forces the fresh block
into any key satisfying `Coverage` and `KeyCovers`. With agreement on the
whole key, a witness for the visit at `L` would have to represent `t = 9`.
The block is unissued at entry, so this witness shows precisely what the
entry-issued restriction excludes. `key` and `footprint` in the check are
model parameters, and `Coverage` and `KeyCovers` are local model premises
on that fixture.

```lean
Checks.loop_entry_premises : Checks.innerEntry.ProducerSound ∧
  Checks.innerEntry.Coverage ∧ Checks.innerEntry.KeyCovers ∧ Checks.innerEntry.InnerSound Checks.innerStates
'Checks.loop_entry_premises' depends on axioms: [propext, Quot.sound]

Checks.loop_member_matches : Checks.innerEntry.Matches FunMem.allocatorAgreement Checks.innerMember
'Checks.loop_member_matches' depends on axioms: [propext]

Checks.loop_shared_inner : ∀ (i : Int),
  i ∈ [0, 1] →
    ∃ m w env,
      Visit Checks.innerSubj { env := Checks.noLocals, mem := Checks.innerMember } 4 env m ∧
        Memory.load m 0 = some (Value.int i) ∧
          Checks.predicates.γ (Checks.innerStates 4) w ∧ AgreeOn Checks.innerEntry.key w m
'Checks.loop_shared_inner' depends on axioms: [propext, Quot.sound]

Checks.loop_inner_outside_key : ∃ m env,
  Visit Checks.innerSubj { env := Checks.noLocals, mem := Checks.innerMember } 4 env m ∧
    ∀ (w : FunMem), Checks.predicates.γ (Checks.innerStates 4) w → ¬AgreeOn [1] w m
'Checks.loop_inner_outside_key' depends on axioms: [propext]

Checks.loop_first_visit_insufficient : (∃ env m,
    Visit Checks.innerSubj { env := Checks.noLocals, mem := Checks.innerProducer } 4 env m ∧
      Checks.loopFirstVisitState 4 m) ∧
  ¬Checks.innerEntry.InnerSound Checks.loopFirstVisitState
'Checks.loop_first_visit_insufficient' depends on axioms: [propext]

Checks.fresh_local_must_be_keyed : ∀ (key : BlockSet) (footprint : Footprint),
  (Checks.freshLocalEntry key footprint).Coverage →
    (Checks.freshLocalEntry key footprint).KeyCovers →
      ¬Memory.Issued FunMem.empty 0 ∧
        (Checks.freshLocalRun 2).fst = [Event.scopeEnter 0, Event.read 0] ∧
          0 ∈ key ∧
            ∃ env m,
              Visit Checks.freshLocalSubject { env := Checks.noLocals, mem := FunMem.empty } 11 env m ∧
                Memory.load m 0 = some (Value.int 9) ∧
                  ∀ (w : FunMem), AgreeOn key w m → Memory.load w 0 = some (Value.int 9)
'Checks.fresh_local_must_be_keyed' depends on axioms: [propext]
```

## Saved states and the public query

**Kind.** OCaml obligation, open.

**Eva symbols and evidence.** `Cache_producer.inner` references the saved
cvalue states by the producing callstack when recording is enabled for both
the function and cvalue. `Engine.Store.register_state` joins registrations
for the same control point and callstack. The prior producer regression
observed a query returning `{1; 2}` at one producing callstack whose first
entry had input `{1}`. This checks the join. Coverage of every producing visit under
`InnerSound` remains open. See [Provenance, storage and lookup](cache-producer.md#provenance-storage-and-lookup).

**Open for #38.** Derive `entry.Matches a m` for each covered current memory
from an admitted match. In particular, establish
`∃ w, d.γ entry.input w ∧ ReplayAgreement a entry.key entry.footprint.writes w m`
with common program, subject and entry bindings. Compose Exit with the
`W_exit` overlay and the frame proof using the current-input sweep
condition, including agreement off the overlay for initially absent or
released bindings. The hit proof also owes the four side-table obligations
and composition with the entry's Safety and Reach guarantees.
[Hit composition](reuse-operation.md#reuse-sound-for-cvalue).

**Open for public Inner reconstruction.** Establish the connection between
saved states and `InnerSound`. Use the lemma on entry-issued key blocks
where a reference is available. Justify the other blocks, including
fresh locals in the lookup key, with per-member data, the prefix's sweep
and write effects, or top. The query proof must address after-statement
observations separately. Coverage and the argument for offsets remain
OCaml obligations.
