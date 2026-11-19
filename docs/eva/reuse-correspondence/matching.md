# Matching

Claims about the match of a current input with the stored input of a cache
entry: which current memories the match puts in the stored input, and which
memory of the stored input agrees with each of them on the matching key. The
laws of a domain and the product of two domains are defined in
[Domain laws](domain-laws.md#the-laws-in-the-model). The closure that memexec
computes today is in [Call-cache
seam](call-cache-seam.md#closure-of-the-memexec-key-under-relate).

The evidence is that of [Domain laws](domain-laws.md#evidence-common-to-the-entries):
tree of `lean/` `8fb8b87666889ddca7376bdd0555803062ab973a`, at commit
`fb938739594412912b0bc9de1e8a28d9454b32af`, `cd lean && lake build --wfail`
run on 2026-11-18 on an extraction of that commit, exit status 0. CI: [run 44383251659](https://github.com/nyandrianinamamy/frama-c/actions/runs/44383251659) succeeded on this tree. The
[rebuild for entry construction](domain-laws.md#evidence-common-to-the-entries)
also checks these lemmas, with the same axiom output.

## Kinds of the hypotheses

The hypotheses of the lemmas below, with their kind, are:

| Hypothesis | Kind | Status |
|---|---|---|
| `[Memory M]`: the memory meets the laws of `Memory` | Proved in Lean for `FunMem` | Done ([frame entry](frame.md#frame-lemma-with-lexical-sweeps)) |
| `Combinable M`: two memories combine on any set of blocks | Proved in Lean for `FunMem`; for Eva's concrete memories, an argument in prose is owed | Done in Lean; open for Eva, with the missing premise under the product lemma |
| `FilterSound`, weak form, of each domain | OCaml obligation, per domain | cvalue: argued in prose ([reuse operation](reuse-operation.md#filter-sound-for-cvalue)); other domains pending |
| `RelateSound` of each domain (clause `decomposes`) | OCaml obligation, per domain | cvalue: argued in prose ([reuse operation](reuse-operation.md#relate-empty-for-cvalue)); other domains pending; fails for the equality domain on `y == z` with the key `{x}` ([domain laws](domain-laws.md#the-equality-domain-fails-relate-sound-on-a-closed-key)), not for every identity `filter` |
| `Closed K S`: the key is closed in the stored input | OCaml obligation | Memexec: [source inspection](call-cache-seam.md#closure-of-the-memexec-key-under-relate); supplied entries: checked by `Cache_entry.Make.make`, source inspection ([reuse operation](reuse-operation.md#the-match-by-equality)) |
| `∃ w, γ S w`: the stored concretisation is not empty | OCaml obligation | Open: no argument recorded; supplied entries refuse a `Bottom` input only ([reuse operation](reuse-operation.md#filter-exact-on-the-stored-input-for-cvalue)) |
| Inclusion of the filtered current input in the filtered stored input, on concretisations | OCaml obligation | Memexec: equality of filtered states, source inspection; supplied entries: equality of two projections on the key, source inspection ([reuse operation](reuse-operation.md#the-match-by-equality)) |
| `ExactOn K S`: `filter` exact on the stored input | Proved in Lean from the hypotheses above | Done (product lemma) |
| `γ C m`: the current input covers the current memory | Relied on from Eva | The soundness of the analysis of the caller up to the call; not checked here |

Each row is discussed in the entry that uses it. No lemma below takes the
law `Extensional`; under it, the hypotheses and conclusions are the same for
every list with the members of the key ([domain
laws](domain-laws.md#closure-depends-on-the-members-of-the-key-only)).

## Match lemma

**Kind.** Proved in Lean.

**Claim.** Let `C` be the current input and `S` the stored input of a domain,
and `K` a key. If `filter` is sound in the weak form on `C`, and the filtered
current input `filter K C` is included in the filtered stored input
`filter K S` (on their concretisations), then each memory `m` that `C` covers
is covered by `filter K S`; `match_filtered` states this part alone, and it
needs neither exactness nor closure. If moreover `filter` is exact on `S`
for `K`, then some memory `m'` covered by `S` agrees with `m` on `K`.

**Scope.** The model. Any domain on any memory type with the laws of
`Memory`. The lemma needs no hypothesis that the current input is not
bottom: a memory covered by `C` is given. It needs no hypothesis on the
closure of `K` in `C` or in `S`; closure enters through exactness (see
[Product lemma](#product-lemma)).

**Declarations.** `ReuseModel.Domain.match_filtered` and
`ReuseModel.Domain.match_lemma`, in
[`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean).
`match_lemma` takes its first conclusion from `match_filtered`.

**Statements.**

```lean
@match_filtered : ∀ {M : Type} {d : Domain M} {K : BlockSet} {C S : d.State},
  (∀ (m : M), d.γ C m → d.γ (d.filter K C) m) →
    (∀ (m : M), d.γ (d.filter K C) m → d.γ (d.filter K S) m) → ∀ {m : M}, d.γ C m → d.γ (d.filter K S) m
@match_lemma : ∀ {M : Type} [inst : Memory M] {d : Domain M} {K : BlockSet} {C S : d.State},
  (∀ (m : M), d.γ C m → d.γ (d.filter K C) m) →
    (∀ (m : M), d.γ (d.filter K C) m → d.γ (d.filter K S) m) →
      d.ExactOn K S → ∀ {m : M}, d.γ C m → d.γ (d.filter K S) m ∧ ∃ m', d.γ S m' ∧ AgreeOn K m m'
```

**Hypotheses.** `match_filtered` takes 2, 3 and 5 only; `match_lemma` takes
all five.

1. `[Memory M]`. Proved in Lean for `FunMem`.
2. `∀ m, d.γ C m → d.γ (d.filter K C) m`: weak `filter` soundness on the
   current input; `d.FilterSound` gives it for every input. OCaml
   obligation per domain, pending
   ([domain laws](domain-laws.md#the-weak-form-of-filter-sound-suffices-for-the-match-and-product-lemmas)).
3. `∀ m, d.γ (d.filter K C) m → d.γ (d.filter K S) m`: inclusion of the
   filtered inputs, stated on concretisations because the model has no order
   on states. OCaml obligation. Memexec accepts an entry when the filtered
   current state is found in a table keyed by the filtered stored states
   (`Mem_exec.Make.find_match_in_previous`, `Domain.Hashtbl.find` on
   `Domain.filter binputs state`), so the two filtered states are equal for
   `Domain.equal`; equal states have equal concretisations, which gives the
   inclusion. The reuse operation on supplied entries compares
   `Domain.filter K state` with the stored input by `Domain.equal`
   (`Cache_entry.Make.check`); for cvalue, two equal projections on K cover
   the same memories when each is read through its support
   ([reuse operation](reuse-operation.md#interpretation-of-cvalue-states-and-of-their-projections),
   P2). Source inspection only.
4. `d.ExactOn K S`: `filter` exact on the stored input for `K`. Proved in
   Lean from the hypotheses of the [product lemma](#product-lemma).
5. `d.γ C m`: the current input covers the current memory. Relied on from
   Eva: it is the soundness of the analysis of the caller up to the call,
   under which the claim is stated.

**Depends on.** [Product lemma](#product-lemma), for hypothesis 4.

**Evidence.**

```
'ReuseModel.Domain.match_filtered' does not depend on any axioms
'ReuseModel.Domain.match_lemma' does not depend on any axioms
```

**Open.** The OCaml obligations of hypotheses 2 and 3.

## Product lemma

**Kind.** Proved in Lean.

**Claim.** Let `S` be the stored input of the product of two domains, and `K`
a key closed in `S` under the union of the two `relate`. If both components
meet `relate` sound, the concretisation of `S` is not empty, and memories
can be combined, then `filter` is exact on `S` for `K`: each memory covered by
`filter K S` agrees on `K` with a memory covered by `S`. Closure is required
in the stored input only. The components need not meet `filter` exact:
exactness of the product is derived from the decomposition of each
component. Taking one witness per component from their own exactness would
not do, since the two witnesses need not be one memory.

**Scope.** The model. The proof takes a memory `w` covered by `S`, combines
the given memory on `K` with `w` outside `K`, and shows with the clauses
`onKey` and `split` of each component that the combination is covered by
`S`. The same argument for one domain is `exactOn_of_decomposes`, and
`filterExact_of_relateSound` derives the law `filter` exact from `relate`
sound. A product of more than two domains is a nested product:
`relateSound_prod` gives `relate` sound for the inner product.

**Declarations.** `ReuseModel.Domain.product_lemma`, with
`ReuseModel.Domain.exactOn_of_decomposes` and
`ReuseModel.Domain.filterExact_of_relateSound`, in
[`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean); and
`ReuseModel.FunMem.combinable`, in the same file.

**Statements.**

```lean
@product_lemma : ∀ {M : Type} [inst : Memory M] {d₁ d₂ : Domain M} {K : BlockSet} {S : (d₁.prod d₂).State},
  Combinable M →
    d₁.RelateSound → d₂.RelateSound → (d₁.prod d₂).Closed K S → (∃ w, (d₁.prod d₂).γ S w) → (d₁.prod d₂).ExactOn K S
@exactOn_of_decomposes : ∀ {M : Type} [inst : Memory M] {d : Domain M} {K : BlockSet} {S : d.State},
  Combinable M → d.Decomposes K S → (∃ w, d.γ S w) → d.ExactOn K S
@filterExact_of_relateSound : ∀ {M : Type} [inst : Memory M] {d : Domain M},
  Combinable M → d.RelateSound → d.FilterExact
FunMem.combinable : Combinable FunMem
```

**Hypotheses.**

1. `[Memory M]`. Proved in Lean for `FunMem`.
2. `Combinable M`: for every set of blocks `B` and memories `m`, `w`, some
   memory agrees with `m` on `B` and with `w` outside `B`. The interface
   `Memory` has no operation that builds such a memory, so this is a
   hypothesis. Proved in Lean for `FunMem` (`FunMem.combinable`: the cells of
   `m` on `B`, those of `w` elsewhere). For Eva, open. That a concrete
   memory gives each base its own content does not show that the combined
   memory is a concrete memory. A search of `plugins/eva/src` and
   `src/kernel/services/abstract_interp` for concrete memories, states,
   stores or values finds them in comments only, with no definition:
   `plugins/eva/src/domains/abstract_domain.ml` describes states as
   abstractions of "the set of possible concrete states" without defining
   that set. The missing premise: the concrete memories over which the
   concretisations of Eva's states range are closed under the splice on a
   set of bases. For concrete memories `m` and `w` and a set `B` of bases,
   the memory that takes from `m` the liveness and the content of each base
   of `B`, and from `w` those of every other base, must be a concrete
   memory. No invariant of the concrete memories may then relate a base of
   `B` to a base outside `B`, such as the joint lifetime of the locals of one
   call frame, or a pointer, held in a base of `B`, to a base outside `B`
   that is not live in `w`. The model has whole blocks only; sub-block
   access is a known difference of the model
   ([`lean/README.md`](../../../lean/README.md), "What the model leaves
   out").
3. `d₁.RelateSound`, `d₂.RelateSound`: OCaml obligation per domain. Only the
   clause `decomposes` is used, on `K`. Eva's contract for `relate`
   (`Abstract_domain.Caching.relate`, in
   `plugins/eva/src/domains/abstract_domain.ml`) asks for the bases whose
   value may affect the properties inferred on the given bases; it does not
   state the decomposition. The equality domain fails the clause on
   `y == z` with the key `{x}`
   ([domain laws](domain-laws.md#the-equality-domain-fails-relate-sound-on-a-closed-key));
   an identity `filter` alone does not make a domain fail it. Arguments per
   domain pending.
4. `(d₁.prod d₂).Closed K S`: the key is closed in the stored input under the
   union of the two `relate`. OCaml obligation. Eva's product computes
   `relate` as the join of the two results
   (`plugins/eva/src/domains/domain_product.ml`), as `Domain.prod` does.
   Memexec iterates `relate` on the stored input
   ([Closure of the memexec key under
   relate](call-cache-seam.md#closure-of-the-memexec-key-under-relate),
   source inspection); the reuse operation on supplied entries checks it in
   `Cache_entry.Make.make`, and also checks closure in the current input
   ([reuse operation](reuse-operation.md#the-match-by-equality), source
   inspection).
5. `∃ w, (d₁.prod d₂).γ S w`: the concretisation of the stored input is not
   empty. OCaml obligation, open
   ([Non-emptiness](#non-emptiness-of-the-stored-concretisation-stays-a-hypothesis)).

**Depends on.** [The product keeps the
laws](domain-laws.md#the-product-keeps-the-laws), for `closed_prod_iff` and
`decomposes_prod`.

**Evidence.**

```
'ReuseModel.Domain.product_lemma' depends on axioms: [propext]
'ReuseModel.Domain.exactOn_of_decomposes' does not depend on any axioms
'ReuseModel.Domain.filterExact_of_relateSound' does not depend on any axioms
'ReuseModel.FunMem.combinable' depends on axioms: [propext, Quot.sound]
```

`propext` in `product_lemma` comes from the definition of `Domain.prod`.
`FunMem.combinable` decides membership in a list of blocks and uses no
classical choice.

**Open.** The OCaml obligations of hypotheses 3, 4 and 5, and the premise
of hypothesis 2 for Eva's concrete memories.

## Closure in the stored input suffices for the match

**Kind.** Proved in Lean.

**Claim.** For a product of two domains, the match lemma with the exactness
given by the product lemma needs the key to be closed in the stored input
only. Under `filter` sound and `relate` sound for both components, closure of
`K` in the stored input `S`, a non-empty concretisation of `S`, combinable
memories, and the inclusion of `filter K C` in `filter K S`, each memory
covered by the current input `C` agrees on `K` with a memory covered by `S`.
Nothing is required of the closure of `K` in `C`.

**Scope.** The model. The claim answers whether closure in the stored input
alone suffices for the match: it does. It does not decide whether Eva's
check that the key is closed in the current input
(`Mem_exec.Make.find_match_in_previous` tests that `Domain.relate binputs
state` is included in `binputs` on the current state) can be removed: the
specification keeps that check for from-scratch equality and removes it only
if the from-scratch tests show no difference. The
[checked relational example](whole-product.md#projection-without-current-side-closure-can-lose-a-relation)
shows that dropping the check can lose precision even with a sound hit.
[Entry construction](entry.md)
also needs write-target liveness and allocation agreement for the same
producing witness. A [checked case](entry.md#checked-cases) gives a
successful projection with no allocator agreement for any stored
witness. Deriving the full witness is an open obligation for the
within-analysis hit.

**Declaration.** `ReuseModel.Domain.projected_match`, in
[`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean).

**Statement.**

```lean
@projected_match : ∀ {M : Type} [inst : Memory M] {d₁ d₂ : Domain M} {K : BlockSet} {C S : (d₁.prod d₂).State},
  Combinable M →
    d₁.FilterSound →
      d₂.FilterSound →
        d₁.RelateSound →
          d₂.RelateSound →
            (d₁.prod d₂).Closed K S →
              (∃ w, (d₁.prod d₂).γ S w) →
                (∀ (m : M), (d₁.prod d₂).γ ((d₁.prod d₂).filter K C) m → (d₁.prod d₂).γ ((d₁.prod d₂).filter K S) m) →
                  ∀ {m : M}, (d₁.prod d₂).γ C m → ∃ m', (d₁.prod d₂).γ S m' ∧ AgreeOn K m m'
```

**Hypotheses.** Those of the [match lemma](#match-lemma) and of the
[product lemma](#product-lemma), with their kinds, except `ExactOn`, which
the product lemma supplies. `d₁.FilterSound` and `d₂.FilterSound` are used on
the current input only.

**Depends on.** [Match lemma](#match-lemma), [Product
lemma](#product-lemma).

**Evidence.**

```
'ReuseModel.Domain.projected_match' depends on axioms: [propext]
```

`Checks.valueProd_match` applies the lemma to a concrete product
([domain laws](domain-laws.md#the-laws-can-be-met-together)). Its proof
gives the inclusion by the equality of the filtered inputs; that the stored
input does not cover the current memory is by inspection, not part of the
statement.

**Open.** The OCaml obligations listed under the two lemmas.

## Non-emptiness of the stored concretisation stays a hypothesis

**Kind.** Proved in Lean.

**Claim.** The product lemma does not hold without its non-emptiness
hypothesis. Take the product of a non-relational domain with itself, whose
first component holds `y ∈ {0}` and whose second holds `y ∈ {1}`, and the key
`{x}`. Both components meet `relate` sound and each covers some memory; the
key is closed and the product decomposes on it. The product covers no
memory, and `filter` is not exact on it for `{x}`: the filtered state covers
every memory, and no memory of the stored input agrees with it on `{x}`.
Non-emptiness of the stored concretisation therefore stays an explicit
hypothesis.

**Scope.** The model. A product can have an empty concretisation while
neither component is bottom; this is such a case. The counterexample is about
the product lemma with its other hypotheses; it does not show a hit in Eva.
Whether Eva can store an input with an empty concretisation is not
established, and nothing in this record argues that it cannot.

**Declaration.** `Checks.nonempty_needed`, in
[`lean/Checks/Domains.lean`](../../../lean/Checks/Domains.lean).

**Statement.** `valueProd` is the product of `valueDom FunMem` with itself,
`emptyS` the state `([(1, [.int 0])], [(1, [.int 1])])`.

```lean
nonempty_needed : (valueDom FunMem).RelateSound ∧
  (∃ w, (valueDom FunMem).γ emptyS.fst w) ∧
    (∃ w, (valueDom FunMem).γ emptyS.snd w) ∧
      valueProd.Closed [0] emptyS ∧
        valueProd.Decomposes [0] emptyS ∧ (¬∃ w, valueProd.γ emptyS w) ∧ ¬valueProd.ExactOn [0] emptyS
```

**Hypotheses.** None: a closed statement.

**Depends on.** [The product keeps the
laws](domain-laws.md#the-product-keeps-the-laws), for `closed_prod_iff` and
`decomposes_prod`.

**Evidence.**

```
'Checks.nonempty_needed' depends on axioms: [propext, Quot.sound]
```

**Open.** Eva must establish nonemptiness of the stored concretisation
for entry construction and the product exactness derivation. For a
projected hit, the proof uses stored-side exactness and a joint
key, write-liveness and allocator witness.
[Hit soundness](hit.md#hit-soundness).
