# Whole-product matching and relational precision

## Whole-product equality supplies the input witness

**Kind.** Proved in Lean.

**Claim.** Compare the entire current domain state with the entire stored
input in the same namespace. Every memory covered by the current input
serves as its own stored witness. Key contents, liveness of all write
targets in `W` and the allocator relation agree reflexively. This is an
input witness. Replay still requires the obligations of the next entry.

**Scope.** The model fixes one subject and one entry environment for the
two executions. Equality is on `d.State`, which includes every component
when `d` is a product. There is no renaming. No projection, closure, domain
law or state order enters this witness proof.

**Declarations.** `ReuseModel.CacheEntry.WholeProductMatch` and
`ReuseModel.CacheEntry.whole_product_witness` in
[`Hit.lean`](../../../lean/ReuseModel/Hit.lean).

```text
@WholeProductMatch : {M : Type} → {d : Domain M} → CacheEntry d → d.State → Prop
'ReuseModel.CacheEntry.WholeProductMatch' depends on axioms: [propext]
```

```text
@whole_product_witness : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {a : AllocatorAgreement M}
  {cur : d.State},
  entry.WholeProductMatch cur →
    ∀ {m : M}, d.γ cur m → d.γ entry.input m ∧ ReplayAgreement a entry.key entry.footprint.writes m m
'ReuseModel.CacheEntry.whole_product_witness' depends on axioms: [propext]
```

**Hypotheses.**

| Premise | Kind and status |
|---|---|
| `M : Type`, `d : Domain M`, `entry : CacheEntry d`, `cur : d.State`, `m : M` | Model parameters. The common namespace, code and entry bindings are model restrictions. Correspondence at lookup is an [open OCaml obligation](#whole-product-admission-in-eva). |
| `[Memory M]`, `a : AllocatorAgreement M` | Model interfaces. Their laws are proved for `FunMem`. This witness uses reflexivity of `a.rel` on the same memory. |
| `entry.WholeProductMatch cur` | Lookup premise. `cur = entry.input` in the model, and an [open OCaml obligation](#whole-product-admission-in-eva) for the comparison at an Eva lookup. |
| `d.γ cur m` | Local premise selecting the current member. Gives a concrete member whenever the theorem is applied. |

**Depends on.** [A producing memory matches its own entry](entry.md#a-producing-memory-matches-its-own-entry)
for the meaning of replay agreement.

**Evidence.** The statements and axiom lines above are from the local build
of the [checked tree](#evidence-for-these-entries).

## Hit under whole-product equality

**Kind.** Proved in Lean.

**Claim.** With a sound entry, whole-product equality, the unchanged frame
condition and sound reuse for each outcome, the hit covers Exit on normal
exits and Reach and Safety on every finite prefix, including validity at
each visit of an assertion that the entry does not report as violated.
The theorem uses `W_exit` for the overlay. It uses the whole-product
witness as the `Matches` premise of `hit_of_matches`.

**Scope.** The model, with the same subject and entry bindings and valid
skipped code and effects. The frame condition still applies to the
current holders on their normal-exit trace. The theorem covers whole
blocks. Each supported Eva domain still owes its reuse argument.
The four [side-table obligations](hit.md#side-table-obligations-for-skipped-work)
still apply to nested skipped work. The equality compares abstract inputs
and does not establish anything about table access coverage or replay.

**Declaration.** `ReuseModel.CacheEntry.hit_of_whole_product` in
[`Hit.lean`](../../../lean/ReuseModel/Hit.lean). The checked case in
[`WholeProduct.lean`](../../../lean/Checks/WholeProduct.lean) obtains a hit
from equal inputs and rejects differences in either component. The two
altered inputs retain the same projection on `{x}` (the equality-component
case is checked in the precision example below).

```text
@hit_of_whole_product : ∀ {M : Type} [inst : Memory M] {d : Domain M} {entry : CacheEntry d} {a : AllocatorAgreement M}
  {cur : d.State},
  entry.Sound a →
    entry.WholeProductMatch cur →
      (∀ (o : Outcome), d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o)) →
        (∀ (m : M), d.γ cur m → entry.NoFrameRewrite m) → ∀ (m : M), d.γ cur m → entry.HitObservations cur m
'ReuseModel.CacheEntry.hit_of_whole_product' depends on axioms: [propext, Quot.sound]
```

```text
Checks.whole_product_copy_hit :
  have other := ([(0, [ReuseModel.Value.int 0, ReuseModel.Value.int 1]), (1, [ReuseModel.Value.int 1])], []);
  Checks.copyEntry.WholeProductMatch Checks.copyEntry.input ∧
    Checks.copyEntry.HitObservations Checks.copyEntry.input (Checks.copyMem 0 0 0) ∧
      ¬Checks.copyEntry.WholeProductMatch Checks.copyCurrent ∧
        Checks.copyProduct.filter Checks.copyEntry.key other =
            Checks.copyProduct.filter Checks.copyEntry.key Checks.copyEntry.input ∧
          ¬Checks.copyEntry.WholeProductMatch other
'Checks.whole_product_copy_hit' depends on axioms: [propext, Quot.sound]
```

**Hypotheses.**

| Premise | Kind and status |
|---|---|
| `M : Type`, `d : Domain M`, `entry : CacheEntry d`, `cur : d.State`, `[Memory M]`, `a : AllocatorAgreement M`, `entry.WholeProductMatch cur` | Same model parameters, interfaces and lookup premise as the [input witness](#whole-product-equality-supplies-the-input-witness). |
| `entry.Sound a` | Proved in Lean by `sound_of_producer` from a nonempty stored input, producer soundness, coverage and key coverage. Applicability to the actual entry remains an OCaml obligation. [Entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage) |
| `∀ o, d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o)` | Local domain-law premise for every outcome. The argument for each admitted Eva domain and the actual exit bindings is an open OCaml obligation. [Reuse sound for cvalue](reuse-operation.md#reuse-sound-for-cvalue) |
| `∀ m, d.γ cur m → entry.NoFrameRewrite m` | Open OCaml obligation at admission. For every current member, the actual sweeps of a normal exit leave every off-overlay binding unchanged. [Sweep admission](frame.md#admission-condition-for-sweeps-of-own-locals) |
| `m : M`, `d.γ cur m` in the pointwise conclusion | Model parameter and local membership premise. |

The checked case and its fixture declarations are closed model data and
statements. The integer arguments `x`, `w` and `z` of `copyMem` are
model parameters. The local `other` in the checked case changes only the
constraint on `w` outside the key.

**Depends on.** [Input witness](#whole-product-equality-supplies-the-input-witness)
and [common hit argument](hit.md#hit-soundness).

**Evidence.** See the statements and axiom lines above and the
[checked tree](#evidence-for-these-entries).

## Projection without current-side closure can lose a relation

**Kind.** Proved in Lean.

**Claim.** The statement is `w = x`, with blocks 0, 1 and 2 for `x`,
`w` and `z`, and key `[0]`. The stored input permits `x ∈ {0, 1}`
independently of `z`. Both inputs require a live `w` initially holding 0,
and the current input adds `x = z`. The key is closed in the stored
input and fails closure in the current input because `relate` returns
`z`. The filtered products are equal. The actual `CacheEntry.hit`
theorem applies to every current member: each already belongs to the
stored input, so a single reflexive witness satisfies every replay
agreement, and this assignment has no sweep.

`copyMem 1 0 0` reaches the stored exit `copyMem 1 1 0`. The current
member `copyMem 0 0 0` exits with `w = 0`. Reuse takes `w` from the
first exit and `x,z` from the current frame, so it admits `copyMem 0 1 0`.
The stored exit relates `w` and `x`; that relation crosses the write
boundary and the reuse operation drops it. The current relation
`x = z` is preserved. The fresh exit summary is separately proved
producer-sound for the current input and entails `w = z` at normal
completion, which excludes `copyMem 0 1 0`.

**Scope.** An existence proof for a product of the value domain and an
example equality domain that projects its pairs to the key. This example
uses a genuine projection. Eva's equality domain has an identity
`filter`, and its [separate checked case](domain-laws.md#the-equality-domain-fails-relate-sound-on-a-closed-key)
has a different purpose. The precision example proves coverage and a
strict difference at this witness, using a sound fresh relational exit
summary. The model leaves analyzer iteration outside its scope. The
specification's current-side closure check stays in force.

**Declarations.** `Checks.projected_copy_loses_relation` and its fixture
data in [`WholeProduct.lean`](../../../lean/Checks/WholeProduct.lean).

```text
Checks.copyProduct : ReuseModel.Domain ReuseModel.FunMem
'Checks.copyProduct' depends on axioms: [propext, Quot.sound]
```

```text
Checks.copyEntry : ReuseModel.CacheEntry Checks.copyProduct
'Checks.copyEntry' depends on axioms: [propext, Quot.sound]
```

```text
Checks.copyCurrent : Checks.copyProduct.State
'Checks.copyCurrent' depends on axioms: [propext, Quot.sound]
```

```text
Checks.copyFresh : ReuseModel.CacheEntry Checks.copyProduct
'Checks.copyFresh' depends on axioms: [propext, Quot.sound]
```

```text
Checks.copyMem (x w z : Int) : ReuseModel.FunMem
'Checks.copyMem' depends on axioms: [propext]
```

```text
Checks.projected_copy_loses_relation :
  Checks.copyEntry.Sound ReuseModel.FunMem.allocatorAgreement ∧
    Checks.copyProduct.Closed Checks.copyEntry.key Checks.copyEntry.input ∧
      ¬Checks.copyProduct.Closed Checks.copyEntry.key Checks.copyCurrent ∧
        Checks.copyProduct.filter Checks.copyEntry.key Checks.copyCurrent =
            Checks.copyProduct.filter Checks.copyEntry.key Checks.copyEntry.input ∧
          (∀ (m : ReuseModel.FunMem),
              Checks.copyProduct.γ Checks.copyCurrent m → Checks.copyEntry.HitObservations Checks.copyCurrent m) ∧
            ReuseModel.Exit Checks.copyEntry.subject { env := Checks.copyEntry.env, mem := Checks.copyMem 1 0 0 }
                ReuseModel.Outcome.completed (Checks.copyMem 1 1 0) ∧
              ReuseModel.Exit Checks.copyEntry.subject { env := Checks.copyEntry.env, mem := Checks.copyMem 0 0 0 }
                  ReuseModel.Outcome.completed (Checks.copyMem 0 0 0) ∧
                Checks.copyProduct.γ
                    (Checks.copyProduct.reuse Checks.copyEntry.footprint.exitWrites Checks.copyCurrent
                      (Checks.copyEntry.exit ReuseModel.Outcome.completed))
                    (Checks.copyMem 0 1 0) ∧
                  Checks.copyFresh.ProducerSound ∧
                    (∀ (m : ReuseModel.FunMem),
                        Checks.copyProduct.γ (Checks.copyFresh.exit ReuseModel.Outcome.completed) m →
                          ReuseModel.Memory.load m 1 = ReuseModel.Memory.load m 2) ∧
                      ¬Checks.copyProduct.γ (Checks.copyFresh.exit ReuseModel.Outcome.completed) (Checks.copyMem 0 1 0)
'Checks.projected_copy_loses_relation' depends on axioms: [propext, Quot.sound]
```

**Hypotheses.** The existence check is closed. In its conclusion,
`m : FunMem` is a model parameter and each `γ` antecedent is a local
membership premise. The fresh summary's `ProducerSound` is proved for
all current members, with membership, normal exits, violations and
visits as the local premises of its fields. The projector's weak filter
soundness and `RelateSound` are proved for the equality component.
Stored nonemptiness, stored closure and the component laws discharge
the product lemma. The fixture proves coverage and key coverage for
the producer, replay compatibility, no frame rewrite and the global
reuse law of its product.

**Depends on.** [Product lemma](matching.md#product-lemma),
[sound entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage)
and [projected hit](hit.md#hit-soundness).

**Evidence.** See the statement and axiom line above and the
[checked tree](#evidence-for-these-entries).

## Whole-product admission in Eva

**Kind.** OCaml obligation, open.

**Claim to establish.** After admission, compare the complete active
product with the complete stored input under one interpretation of
domain states and block identities. The lookup must identify the same
body, bindings, effective contracts, call modes and other validity
dependencies. The stored entry and its skipped work still owe producer,
frame, per-domain reuse and side-table obligations. Unsupported effects
or accesses, `relate = Top`, an oversized key and missing reuse
arguments still cause the specified refusal.

**Symbols and evidence.** The supplied-entry path documented in
[The match by equality](reuse-operation.md#the-match-by-equality) runs
through `Cache_entry.Make.make`, `Cache_entry.Make.find` and
`Call_cache.Make.lookup`. That evidence is for a cvalue-only projection.
For #57 the complete state must reach lookup and the comparison of the
active product must imply the model equality under the shared
interpretation. Show an equality-domain hit on equal products and a
miss when only the off-key fact `y == z` differs, and show the apron
refusal reason. The admitted-domain list, per-domain reuse arguments,
offset argument and test-configuration results remain pending.

**Depends on.** [Hit under whole-product equality](#hit-under-whole-product-equality),
[sweep admission](frame.md#admission-condition-for-sweeps-of-own-locals)
and [skipped-effect obligations](hit.md#side-table-obligations-for-skipped-work).

## Evidence for these entries

Tree of `lean/` `3cbd3b80e1e52e70d5b9b47662ac3568f1e150db` at
`69cf3c1e5449d48ad048f230c80d5d8b2f5325ca`. On a clean archive of that
tree, `cd lean && lake build --wfail` exited 0 with Lean 4.28.0.
The axiom guard accepted all printed declarations. CI is pending.

Each scratch archive started from the same Lean commit. Each change
below made `lake build --wfail` exit 1.

| Scratch change | Checked proof that failed |
|---|---|
| Use only filtered equality as `WholeProductMatch` | `whole_product_witness` cannot transport membership in the unfiltered current input. |
| Drop current membership from the witness theorem | `whole_product_witness` cannot conclude stored membership. |
| Drop whole-product equality from the hit theorem | `hit_of_whole_product` cannot obtain its stored witness. |
| Replace entry soundness with stored nonemptiness | `hit_of_whole_product` cannot use the common hit theorem. |
| Supply the reuse law for `.completed` only | `hit_of_whole_product` cannot cover every outcome. |
| Drop `NoFrameRewrite` | `hit_of_whole_product` cannot establish the unchanged-frame premise. |
| Allow any event list in the copy trace | `copy_coverage` cannot bound the accesses. |
| Use the identity equality filter | The proof of equal projections in `projected_copy_loses_relation` fails. |
| Omit the current equality | The lookup rejection and current nonclosure checks fail. |
| Omit `w = z` from the fresh exit | `projected_copy_loses_relation` cannot obtain the equality from the fresh summary. |
