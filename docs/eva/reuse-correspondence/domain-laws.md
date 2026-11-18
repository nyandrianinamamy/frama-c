# Domain laws

Claims about the laws that an abstract domain meets for the reuse of a cache
entry: `filter` sound, `relate` sound, `filter` exact and `reuse` sound, as
decided in the parent specification,
[issue #32](https://github.com/nyandrianinamamy/frama-c/issues/32), and stated
in [`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean). The
lemmas that use the laws at the match are in [Matching](matching.md).

## The laws in the model

A domain `d : Domain M` has states `d.State`, a concretisation
`d.γ : d.State → M → Prop` to the memories `M` of the semantics, and the
operations `filter`, `relate` and `reuse` on finite sets of blocks
(`BlockSet`, a list). `relate` returns `none` for `Top`. Two memories agree on
a set of blocks (`AgreeOn`) when each block of the set has the same content
(`Memory.load`) in both, and agree outside it (`AgreeOff`) when each other
block does. The laws, as Lean prints them with `#print`:

- `FilterSound d`: `∀ B S m, d.γ S m → d.γ (d.filter B S) m`. This is the weak
  form: `filter` only forgets. The identity is an instance.
- `Closed d B S`: `∃ R, d.relate B S = some R ∧ ∀ b ∈ R, b ∈ B`.
- `Decomposes d B S`, two clauses: `onKey`, membership in
  `γ (filter B S)` depends only on the blocks of `B`
  (`∀ m m', AgreeOn B m m' → d.γ (d.filter B S) m → d.γ (d.filter B S) m'`);
  and `split`, `γ S` is the set of memories of `γ (filter B S)` that agree
  outside `B` with a memory of `γ S`
  (`∀ m, d.γ S m ↔ d.γ (d.filter B S) m ∧ ∃ w, d.γ S w ∧ AgreeOff B m w`).
- `RelateSound d`, two clauses: `decomposes`, `∀ B S, d.Closed B S →
  d.Decomposes B S`; and `existing`, `relate` returns only blocks that exist
  in the state, read as blocks live in every memory the state covers
  (`∀ B S R, d.relate B S = some R → ∀ b ∈ R, ∀ m, d.γ S m → Live m b`).
- `ExactOn d K S`: `∀ m, d.γ (d.filter K S) m → ∃ m', d.γ S m' ∧ AgreeOn K m
  m'`. `FilterExact d` is the law: `ExactOn d K S` for every key `K` closed in
  a state `S` whose concretisation is not empty.
- `ReuseSound d`: `∀ W cur out mc mo c, d.γ cur mc → d.γ out mo → AgreeOn W
  c mo → AgreeOff W c mc → d.γ (d.reuse W cur out) c`. The result covers a
  memory that combines the written blocks of an output memory with the other
  blocks of a current memory, whether or not that whole memory is covered by
  the output.

The product `d₁.prod d₂` covers a memory when both components do; `filter`
and `reuse` work componentwise, and `relate` is the union of the two results,
`Top` when either is `Top`. Eva's product computes `relate` as the join of
the two results and `filter` and `reuse` componentwise
(`plugins/eva/src/domains/domain_product.ml`, `relate`, `filter`, `reuse`).

These are definitions. The claims below are about them.

## Evidence common to the entries

- Checked revision: tree of `lean/` `fcb327481aa376191a1d9a4365b7486dd9c26cc3`,
  at commit `fa2e36b953afe9f2d943a8630b7de465160c5ba6`. Toolchain
  `leanprover/lean4:v4.28.0` (Lean 4.28.0, commit `7e01a1bf5c70`).
- Command: `cd lean && lake build --wfail`, run on 2026-11-18 on an
  extraction of that commit (`git archive`) with no build directory. Exit
  status 0, no warning.
- The `#print axioms` lines below are from that build. `#check_axioms` in
  `lean/Checks/Axioms.lean` fails the build on `sorryAx` or on an axiom other
  than `propext`, `Classical.choice` and `Quot.sound`. No theorem below uses
  `Classical.choice`.
- Statements are as Lean prints them after `open ReuseModel
  ReuseModel.Domain Checks` with `#check @name`.
- CI: the workflow `.github/workflows/lean-model.yml` has not run on this
  tree. Pending until the branch is pushed.

## The laws can be met together

**Kind.** Proved in Lean.

**Claim.** A non-relational domain meets `filter` sound, `relate` sound,
`filter` exact and `reuse` sound, and so does its product with itself, with
the memory `FunMem`, which meets `Combinable`. The projected match applies to
that product on a concrete stored and current input.

**Scope.** The model. `Checks.valueDom` lists, for some blocks, the values
each may hold; `filter B` keeps the blocks of `B`, `relate` returns no block,
and `reuse W` takes the blocks of `W` from the output and the others from the
current input. It stands for the class "exact `filter`, empty `relate`" of
the specification; it is not a model of cvalue.

**Declarations.** `Checks.valueDom_laws` and `Checks.valueProd_match`, in
[`lean/Checks/Domains.lean`](../../../lean/Checks/Domains.lean).

**Statements.**

```lean
valueDom_laws : Combinable FunMem ∧
  (valueDom FunMem).FilterSound ∧
    (valueDom FunMem).RelateSound ∧
      (valueDom FunMem).FilterExact ∧
        (valueDom FunMem).ReuseSound ∧
          ((valueDom FunMem).prod (valueDom FunMem)).FilterSound ∧
            ((valueDom FunMem).prod (valueDom FunMem)).RelateSound ∧
              ((valueDom FunMem).prod (valueDom FunMem)).FilterExact ∧
                ((valueDom FunMem).prod (valueDom FunMem)).ReuseSound
valueProd_match : ∃ m', valueProd.γ matchS m' ∧ AgreeOn [0] (memOf [Value.int 1, Value.int 4, Value.int 4]) m'
```

**Hypotheses.** None: both are closed statements. In `valueProd_match`, the
stored input `matchS` holds `x ∈ {1}` and `y ∈ {0}` in the first component and
`z ∈ {7}` in the second, the current input `matchC` holds `x ∈ {1}` and
`y ∈ {4}`, and blocks `0`, `1`, `2` stand for `x`, `y`, `z`. The two inputs
are equal after filtering on `{x}`, and the current memory `x = 1, y = 4,
z = 4`, which `matchS` does not cover, agrees on `{x}` with a memory of
`matchS`. The proof applies `ReuseModel.Domain.projected_match`.

**Depends on.** [The product keeps the
laws](#the-product-keeps-the-laws), and [Closure in the stored input
suffices for the match](matching.md#closure-in-the-stored-input-suffices-for-the-match)
for `valueProd_match`.

**Evidence.**

```
'Checks.valueDom_laws' depends on axioms: [propext, Quot.sound]
'Checks.valueProd_match' depends on axioms: [propext, Quot.sound]
```

**Open.** None in the model. Whether a domain of Eva meets the laws is an
OCaml obligation per domain and per law, owed by the reuse feature; no such
argument is recorded yet.

## The product keeps the laws

**Kind.** Proved in Lean.

**Claim.** A set of blocks is closed in a product exactly when it is closed
in both components. The product decomposes on a set where both components
decompose. The product meets `filter` sound, `relate` sound and `reuse` sound
when both components do.

**Scope.** The model, for any memory type with the laws of `Memory`. Closure
under the union of the two `relate` is what makes the closure of a key
iterate across components.

**Declarations.** `ReuseModel.Domain.closed_prod_iff`,
`ReuseModel.Domain.decomposes_prod`, `ReuseModel.Domain.filterSound_prod`,
`ReuseModel.Domain.relateSound_prod` and `ReuseModel.Domain.reuseSound_prod`,
in [`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean).

**Statements.**

```lean
@closed_prod_iff : ∀ {M : Type} {d₁ d₂ : Domain M} {B : BlockSet} {S : (d₁.prod d₂).State},
  (d₁.prod d₂).Closed B S ↔ d₁.Closed B S.fst ∧ d₂.Closed B S.snd
@decomposes_prod : ∀ {M : Type} [inst : Memory M] {d₁ d₂ : Domain M} {B : BlockSet} {S : (d₁.prod d₂).State},
  d₁.Decomposes B S.fst → d₂.Decomposes B S.snd → (d₁.prod d₂).Decomposes B S
@filterSound_prod : ∀ {M : Type} {d₁ d₂ : Domain M}, d₁.FilterSound → d₂.FilterSound → (d₁.prod d₂).FilterSound
@relateSound_prod : ∀ {M : Type} [inst : Memory M] {d₁ d₂ : Domain M},
  d₁.RelateSound → d₂.RelateSound → (d₁.prod d₂).RelateSound
@reuseSound_prod : ∀ {M : Type} [inst : Memory M] {d₁ d₂ : Domain M},
  d₁.ReuseSound → d₂.ReuseSound → (d₁.prod d₂).ReuseSound
```

**Hypotheses.** The laws of the components, each an OCaml obligation per
domain of Eva (see the Open item of [The laws can be met
together](#the-laws-can-be-met-together)). `decomposes_prod` uses neither closure nor non-emptiness: the witness
of `split` for the product is the same memory for both components.
`[Memory M]`: the memory meets the laws of the interface `Memory`; proved in
Lean for `FunMem` (see [the frame entry](frame.md#frame-lemma-without-sweeps),
hypothesis 1).

**Depends on.** None.

**Evidence.**

```
'ReuseModel.Domain.closed_prod_iff' depends on axioms: [propext]
'ReuseModel.Domain.decomposes_prod' depends on axioms: [propext]
'ReuseModel.Domain.filterSound_prod' depends on axioms: [propext]
'ReuseModel.Domain.relateSound_prod' depends on axioms: [propext]
'ReuseModel.Domain.reuseSound_prod' depends on axioms: [propext]
```

`propext` enters through the definition of `Domain.prod`, whose `relate` is a
`match` with a default case: `#print axioms ReuseModel.Domain.prod` gives
`[propext]`.

**Open.** None in the model.

## An identity filter does not decompose the state on a closed key

**Kind.** Proved in Lean.

**Claim.** This is the negative case of the projected match. A domain of
equalities between blocks with an identity `filter` holds the single fact
`y == z`. The key `{x}` is closed in that state (while `{y}` is not), the
concretisation of the state is not empty, `filter` is sound in the weak form
and exact on `{x}`, and the clause `split` of the decomposition holds. The
clause `onKey` fails: the memories `x = 0, y = z = 5` and `x = 0, y = 5,
z = 6` agree on `{x}`, and only the first is in `γ (filter {x} S)`. So
`filter` does not decompose the state on `{x}`, and the domain does not meet
`relate` sound, although it meets `filter` sound, `filter` exact, `reuse`
sound and the clause `existing`. At the match, a current input with no fact
is not included in the stored input after filtering on `{x}`, although each
of its memories agrees on `{x}` with a memory of the stored input: the
identity `filter` compares facts outside the key.

**Scope.** The model. `Checks.eqDom` covers a memory when both blocks of
each pair are live and equal; its `relate B` returns the blocks of the pairs
that have a block in `B`, as Eva's equality domain returns the bases of the
expressions equal to an expression that depends on `B`. The case shows that a
domain with an identity `filter` is excluded from the projected match by
`relate` sound, not by `filter` sound. It does not show a hit that is
unsound: the conclusion of the match is not claimed to fail.

**Declarations.** `Checks.identity_filter_negative`,
`Checks.eqDom_not_relateSound`, `Checks.eqDom_not_closed_y`,
`Checks.identity_filter_no_inclusion`, `Checks.eqDom_existing` and
`Checks.eqDom_reuseSound`, in
[`lean/Checks/Domains.lean`](../../../lean/Checks/Domains.lean).

**Statements.** `yz` is the state `[(1, 2)]`, `memYZ` the memory
`x = 0, y = z = 5`, `memYnZ` the memory `x = 0, y = 5, z = 6`, `noFact` the
state `[]`.

```lean
identity_filter_negative : (eqDom FunMem).FilterSound ∧
  (eqDom FunMem).Closed [0] yz ∧
    (∃ w, (eqDom FunMem).γ yz w) ∧
      (eqDom FunMem).ExactOn [0] yz ∧
        (∀ (m : FunMem),
            (eqDom FunMem).γ yz m ↔
              (eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) m ∧ ∃ w, (eqDom FunMem).γ yz w ∧ AgreeOff [0] m w) ∧
          (AgreeOn [0] memYZ memYnZ ∧
              (eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) memYZ ∧
                ¬(eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) memYnZ) ∧
            ¬(eqDom FunMem).Decomposes [0] yz
eqDom_not_relateSound : ¬(eqDom FunMem).RelateSound
eqDom_not_closed_y : ¬(eqDom FunMem).Closed [1] yz
identity_filter_no_inclusion : (eqDom FunMem).γ ((eqDom FunMem).filter [0] noFact) memYnZ ∧
  ¬(eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) memYnZ ∧
    ∀ (m : FunMem), (eqDom FunMem).γ noFact m → ∃ m', (eqDom FunMem).γ yz m' ∧ AgreeOn [0] m m'
@eqDom_existing : ∀ {M : Type} [inst : Memory M] (B : BlockSet) (S : (eqDom M).State) (R : BlockSet),
  (eqDom M).relate B S = some R → ∀ (b : Block), b ∈ R → ∀ (m : M), (eqDom M).γ S m → Live m b
@eqDom_reuseSound : ∀ {M : Type} [inst : Memory M], (eqDom M).ReuseSound
```

**Hypotheses.** None for the closed statements. `eqDom_existing` and
`eqDom_reuseSound` hold for every memory type with the laws of `Memory`.

**Depends on.** None.

**Evidence.**

```
'Checks.identity_filter_negative' depends on axioms: [propext, Quot.sound]
'Checks.eqDom_not_relateSound' depends on axioms: [propext, Quot.sound]
'Checks.eqDom_existing' depends on axioms: [propext, Quot.sound]
'Checks.eqDom_reuseSound' depends on axioms: [propext, Quot.sound]
'Checks.eqDom_not_closed_y' depends on axioms: [propext, Quot.sound]
'Checks.identity_filter_no_inclusion' depends on axioms: [propext, Quot.sound]
```

**Open.** None in the model. The whole-product match, the rule the
specification gives to products with an identity-`filter` component, is a
later proof target.

## The weak form of filter sound suffices for the match and product lemmas

**Kind.** Proved in Lean, for the lemmas named here.

**Claim.** The match and product lemmas need `filter` sound in its weak form
only: `γ S ⊆ γ (filter B S)`. The match lemma uses it on the current input
only; the product lemma does not use it. The strong form, which asks that
`γ (filter B S)` contain every memory that agrees on `B` with a memory of
`γ S`, is a hypothesis of neither lemma. Where `filter` decomposes the state,
the weak form gives the strong form. The domains with an identity `filter`
meet the weak form; on `y == z` with the key `{x}` they do not meet the
strong form, and they fail `relate` sound. They are excluded from the
projected match by `relate` sound.

**Scope.** The match lemma, the product lemma and their composition
`projected_match`. Whether the weak form suffices for the construction of a
sound entry and for the hit is decided by those later proof targets. The
consequence that criterion 2 of issue #35 asks to report on the
specification, for the case where the weak form does not suffice, does not
arise for these lemmas.

**Declarations.** `ReuseModel.Domain.filterStrong_of_decomposes`, in
[`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean); the
statements of `match_lemma`, `product_lemma` and `projected_match`
([Matching](matching.md)); and `Checks.identity_filter_negative`.

**Statement.**

```lean
@filterStrong_of_decomposes : ∀ {M : Type} [inst : Memory M] {d : Domain M} {B : BlockSet} {S : d.State},
  d.FilterSound → d.Decomposes B S → ∀ {m w : M}, d.γ S w → AgreeOn B w m → d.γ (d.filter B S) m
```

**Hypotheses.** `d.FilterSound`, the weak form: an OCaml obligation per
domain. `d.Decomposes B S`: given on a closed set by `relate` sound, an OCaml
obligation per domain. Eva's contract for `filter`
(`Abstract_domain.Caching.filter`, in
`plugins/eva/src/domains/abstract_domain.ml`) says that properties about
other bases can be removed, and that `filter` keeps the projection of the
concretisation on the bases; it does not state the clause `onKey`. The
default `filter` of `Domain_builder.Complete` is the identity
(`plugins/eva/src/domains/domain_builder.ml`).

**Depends on.** [An identity filter does not decompose the state on a closed
key](#an-identity-filter-does-not-decompose-the-state-on-a-closed-key), and
the entries of [Matching](matching.md) for the statements of the three
lemmas.

**Evidence.**

```
'ReuseModel.Domain.filterStrong_of_decomposes' does not depend on any axioms
```

The statements in [Matching](matching.md) show where `FilterSound` is taken:
`match_lemma` takes it on the current input `C` only, `product_lemma` does not
take it, and `projected_match` takes it for the two components.

**Open.** The argument per domain that its `filter` only forgets is owed by
the reuse feature and not recorded.
