import ReuseModel
import Checks.Examples

/-!
# Domains that meet the laws, and two negative cases

* A non-relational domain, `valueDom`, meets every law of a domain, and so
  does its product with itself: the hypotheses of the match and product
  lemmas can be met together.
* An identity `filter` does not qualify for the projected match. The domain
  `eqDom` holds equalities between blocks and has an identity `filter`. With
  the single fact `y == z`, the key `{x}` is closed and the concretisation is
  not empty; `filter` is sound in the weak form and exact on the key. Yet
  membership in the filtered state depends on `y` and `z`, which are outside
  the key: `filter` does not decompose the state, and `eqDom` does not meet
  `relate` sound. A current input with no fact then fails the inclusion of
  the filtered inputs, although each of its memories agrees on `{x}` with a
  memory of the stored input.
* Non-emptiness of the stored concretisation cannot be dropped from the
  product lemma. Two components of a product meet `relate` sound and each
  has a non-empty concretisation; the key is closed; the product has an empty
  concretisation and `filter` is not exact on it.

Blocks `0`, `1` and `2` stand for the variables `x`, `y` and `z`. The
memories are built with `memOf`, from `Checks/Examples.lean`.
-/

namespace Checks

open ReuseModel Memory Domain

/-! ## A non-relational domain -/

section
variable {M : Type} [Memory M]

/-- A non-relational domain. A state lists blocks with the values each may
hold; a memory is covered when each listed block is live and holds one of its
values. `filter B` keeps the blocks of `B`, `relate` returns no block, and
`reuse W` takes the blocks of `W` from the output and the other blocks from
the current input. -/
def valueDom (M : Type) [Memory M] : Domain M where
  State := List (Block × List Value)
  γ S m := ∀ p ∈ S, ∃ v ∈ p.2, load m p.1 = some v
  filter B S := S.filter fun p => decide (p.1 ∈ B)
  relate _ _ := some []
  reuse W cur out :=
    out.filter (fun p => decide (p.1 ∈ W)) ++
      cur.filter (fun p => decide (p.1 ∉ W))

theorem valueDom_filterSound : (valueDom M).FilterSound := by
  intro B S m hm p hp
  simp only [valueDom, List.mem_filter] at hp
  exact hm p hp.1

theorem valueDom_closed (B : BlockSet) (S : (valueDom M).State) :
    (valueDom M).Closed B S :=
  ⟨[], rfl, by simp⟩

theorem valueDom_decomposes (B : BlockSet) (S : (valueDom M).State) :
    (valueDom M).Decomposes B S where
  onKey m m' hag hm p hp := by
    have hB : p.1 ∈ B := by
      simp only [valueDom, List.mem_filter, decide_eq_true_eq] at hp
      exact hp.2
    obtain ⟨v, hv, hl⟩ := hm p hp
    exact ⟨v, hv, (hag p.1 hB).symm.trans hl⟩
  split m := by
    constructor
    · intro hm
      exact ⟨valueDom_filterSound B S m hm, m, hm, fun _ _ => rfl⟩
    · rintro ⟨hf, w, hw, hoff⟩ p hp
      by_cases hB : p.1 ∈ B
      · exact hf p (by simp [valueDom, hp, hB])
      · obtain ⟨v, hv, hl⟩ := hw p hp
        exact ⟨v, hv, (hoff p.1 hB).trans hl⟩

theorem valueDom_relateSound : (valueDom M).RelateSound where
  decomposes B S _ := valueDom_decomposes B S
  existing B S R hR b hb _ _ := by
    simp only [valueDom, Option.some.injEq] at hR
    subst hR
    simp at hb

theorem valueDom_reuseSound : (valueDom M).ReuseSound := by
  intro W cur out mc mo c hc ho hon hoff p hp
  simp only [valueDom, List.mem_append, List.mem_filter,
    decide_eq_true_eq] at hp
  rcases hp with ⟨hp, hW⟩ | ⟨hp, hW⟩
  · obtain ⟨v, hv, hl⟩ := ho p hp
    exact ⟨v, hv, (hon p.1 hW).trans hl⟩
  · obtain ⟨v, hv, hl⟩ := hc p hp
    exact ⟨v, hv, (hoff p.1 hW).trans hl⟩

end

/-- The laws hold together, for `valueDom` on `FunMem` and for its product
with itself. -/
theorem valueDom_laws :
    Combinable FunMem ∧
    (valueDom FunMem).FilterSound ∧ (valueDom FunMem).RelateSound ∧
    (valueDom FunMem).FilterExact ∧ (valueDom FunMem).ReuseSound ∧
    ((valueDom FunMem).prod (valueDom FunMem)).FilterSound ∧
    ((valueDom FunMem).prod (valueDom FunMem)).RelateSound ∧
    ((valueDom FunMem).prod (valueDom FunMem)).FilterExact ∧
    ((valueDom FunMem).prod (valueDom FunMem)).ReuseSound :=
  have hr := relateSound_prod valueDom_relateSound valueDom_relateSound
  ⟨FunMem.combinable, valueDom_filterSound, valueDom_relateSound,
    filterExact_of_relateSound FunMem.combinable valueDom_relateSound,
    valueDom_reuseSound,
    filterSound_prod valueDom_filterSound valueDom_filterSound, hr,
    filterExact_of_relateSound FunMem.combinable hr,
    reuseSound_prod valueDom_reuseSound valueDom_reuseSound⟩

/-- The product of `valueDom` with itself, on `FunMem`. -/
abbrev valueProd : Domain FunMem := (valueDom FunMem).prod (valueDom FunMem)

/-- A stored input: `x ∈ {1}` and `y ∈ {0}` in the first component,
`z ∈ {7}` in the second. -/
def matchS : valueProd.State :=
  ([(0, [.int 1]), (1, [.int 0])], [(2, [.int 7])])

/-- A current input: `x ∈ {1}` and `y ∈ {4}` in the first component, nothing
in the second. -/
def matchC : valueProd.State := ([(0, [.int 1]), (1, [.int 4])], [])

/-- The projected match applies. Filtered on the key `{x}`, which is closed in
`matchS`, the two inputs are equal, as Eva's lookup requires. The memory
`x = 1, y = 4, z = 4` of the current input, which `matchS` does not cover,
agrees on `{x}` with a memory of `matchS`. -/
theorem valueProd_match :
    ∃ m', valueProd.γ matchS m' ∧
      AgreeOn [0] (memOf [.int 1, .int 4, .int 4]) m' := by
  have hS : valueProd.γ matchS (memOf [.int 1, .int 0, .int 7]) := by
    refine ⟨?_, ?_⟩ <;> intro p hp <;> simp [matchS] at hp <;>
      rcases hp with rfl | rfl <;> exact ⟨_, List.mem_singleton_self _, rfl⟩
  have heq : valueProd.filter [0] matchC = valueProd.filter [0] matchS := rfl
  refine projected_match (C := matchC) FunMem.combinable valueDom_filterSound
    valueDom_filterSound valueDom_relateSound valueDom_relateSound
    (closed_prod_iff.mpr ⟨valueDom_closed _ _, valueDom_closed _ _⟩)
    ⟨_, hS⟩ (fun m hm => heq ▸ hm) ?_
  refine ⟨?_, ?_⟩ <;> intro p hp <;> simp [matchC] at hp
  rcases hp with rfl | rfl <;> exact ⟨_, List.mem_singleton_self _, rfl⟩

/-! ## The negative case of the projected match: `y == z` outside `{x}` -/

section
variable {M : Type} [Memory M]

/-- A domain of equalities between blocks, with an identity `filter`. A
memory is covered when, for each pair, both blocks are live and hold the same
value. `relate B` returns the blocks of the pairs that have a block in `B`.
`reuse W` keeps the pairs of the output whose blocks are both in `W` and the
pairs of the current input whose blocks are both outside `W`. -/
def eqDom (M : Type) [Memory M] : Domain M where
  State := List (Block × Block)
  γ S m := ∀ p ∈ S, ∃ v, load m p.1 = some v ∧ load m p.2 = some v
  filter _ S := S
  relate B S :=
    some ((S.filter fun p => decide (p.1 ∈ B ∨ p.2 ∈ B)).flatMap
      fun p => [p.1, p.2])
  reuse W cur out :=
    out.filter (fun p => decide (p.1 ∈ W ∧ p.2 ∈ W)) ++
      cur.filter (fun p => decide (p.1 ∉ W ∧ p.2 ∉ W))

theorem eqDom_filterSound : (eqDom M).FilterSound :=
  fun _ _ _ hm => hm

/-- With an identity `filter`, `filter` is exact on every key: each memory is
its own witness. -/
theorem eqDom_exactOn (K : BlockSet) (S : (eqDom M).State) :
    (eqDom M).ExactOn K S :=
  fun m hm => ⟨m, hm, fun _ _ => rfl⟩

/-- Of the two clauses of the decomposition, `split` holds for an identity
`filter`. -/
theorem eqDom_split (B : BlockSet) (S : (eqDom M).State) (m : M) :
    (eqDom M).γ S m ↔
      (eqDom M).γ ((eqDom M).filter B S) m ∧
        ∃ w, (eqDom M).γ S w ∧ AgreeOff B m w :=
  ⟨fun hm => ⟨hm, m, hm, fun _ _ => rfl⟩, fun h => h.1⟩

/-- Of the two clauses of `relate` sound, `existing` holds: `relate` returns
blocks of the pairs of the state, which are live in every memory it
covers. -/
theorem eqDom_existing (B : BlockSet) (S : (eqDom M).State) (R : BlockSet)
    (hR : (eqDom M).relate B S = some R) (b : Block) (hb : b ∈ R) (m : M)
    (hm : (eqDom M).γ S m) : Live m b := by
  simp only [eqDom, Option.some.injEq] at hR
  subst hR
  simp only [List.mem_flatMap, List.mem_filter, List.mem_cons,
    List.not_mem_nil, or_false] at hb
  obtain ⟨p, ⟨hp, -⟩, hb⟩ := hb
  obtain ⟨v, h₁, h₂⟩ := hm p hp
  rcases hb with rfl | rfl
  · simp [Live, h₁]
  · simp [Live, h₂]

theorem eqDom_reuseSound : (eqDom M).ReuseSound := by
  intro W cur out mc mo c hc ho hon hoff p hp
  simp only [eqDom, List.mem_append, List.mem_filter,
    decide_eq_true_eq] at hp
  rcases hp with ⟨hp, hW₁, hW₂⟩ | ⟨hp, hW₁, hW₂⟩
  · obtain ⟨v, h₁, h₂⟩ := ho p hp
    exact ⟨v, (hon p.1 hW₁).trans h₁, (hon p.2 hW₂).trans h₂⟩
  · obtain ⟨v, h₁, h₂⟩ := hc p hp
    exact ⟨v, (hoff p.1 hW₁).trans h₁, (hoff p.2 hW₂).trans h₂⟩

end

/-- The stored input: the single fact `y == z`. -/
def yz : (eqDom FunMem).State := [(1, 2)]

/-- `x = 0` and `y = z = 5`: covered by `yz`. -/
def memYZ : FunMem := memOf [.int 0, .int 5, .int 5]

/-- `x = 0`, `y = 5` and `z = 6`: agrees with `memYZ` on `{x}`, and is not
covered by `yz`. -/
def memYnZ : FunMem := memOf [.int 0, .int 5, .int 6]

theorem memYZ_mem : (eqDom FunMem).γ yz memYZ := by
  intro p hp
  simp only [yz, List.mem_singleton] at hp
  subst hp
  exact ⟨.int 5, rfl, rfl⟩

theorem memYnZ_not_mem : ¬ (eqDom FunMem).γ yz memYnZ := by
  intro h
  obtain ⟨v, h₁, h₂⟩ := h (1, 2) (List.mem_singleton_self _)
  have e₁ : load memYnZ 1 = some (.int 5) := rfl
  have e₂ : load memYnZ 2 = some (.int 6) := rfl
  rw [e₁] at h₁
  rw [e₂, ← h₁] at h₂
  cases h₂

theorem agree_x : AgreeOn [0] memYZ memYnZ := by
  intro b hb
  simp only [List.mem_singleton] at hb
  subst hb
  rfl

/-- The key `{x}` is closed in `yz`: no pair has a block in it. -/
theorem eqDom_closed_x : (eqDom FunMem).Closed [0] yz :=
  ⟨[], rfl, by simp⟩

/-- `relate` is not empty: `{y}` is not closed in `yz`, since `relate`
returns `z` with it. -/
theorem eqDom_not_closed_y : ¬ (eqDom FunMem).Closed [1] yz := by
  rintro ⟨R, hR, hsub⟩
  have : R = [1, 2] := by
    simp only [eqDom, yz, Option.some.injEq] at hR
    exact hR.symm
  subst this
  exact absurd (hsub 2 (by simp)) (by simp)

/-- The negative case. The key `{x}` is closed in `yz`, the concretisation of
`yz` is not empty, `filter` is sound in the weak form and exact on `{x}`, and
the clause `split` of the decomposition holds. The clause `onKey` fails:
`memYZ` and `memYnZ` agree on `{x}`, and only `memYZ` is in
`γ (filter {x} yz)`. So `filter` does not decompose `yz` on `{x}`. -/
theorem identity_filter_negative :
    (eqDom FunMem).FilterSound ∧ (eqDom FunMem).Closed [0] yz ∧
    (∃ w, (eqDom FunMem).γ yz w) ∧ (eqDom FunMem).ExactOn [0] yz ∧
    (∀ m, (eqDom FunMem).γ yz m ↔
      (eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) m ∧
        ∃ w, (eqDom FunMem).γ yz w ∧ AgreeOff [0] m w) ∧
    (AgreeOn [0] memYZ memYnZ ∧
      (eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) memYZ ∧
      ¬ (eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) memYnZ) ∧
    ¬ (eqDom FunMem).Decomposes [0] yz :=
  ⟨eqDom_filterSound, eqDom_closed_x, ⟨memYZ, memYZ_mem⟩,
    eqDom_exactOn _ _,
    eqDom_split _ _, ⟨agree_x, memYZ_mem, memYnZ_not_mem⟩,
    fun hd => memYnZ_not_mem (hd.onKey memYZ memYnZ agree_x memYZ_mem)⟩

/-- `eqDom` does not meet `relate` sound, although it meets `filter` sound,
`filter` exact, `reuse` sound and the clause `existing` of `relate` sound. -/
theorem eqDom_not_relateSound : ¬ (eqDom FunMem).RelateSound :=
  fun h =>
    identity_filter_negative.2.2.2.2.2.2 (h.decomposes _ _ eqDom_closed_x)

/-- A current input with no fact. -/
def noFact : (eqDom FunMem).State := []

/-- At the match, the current input `noFact` is not included in `yz` after
filtering on `{x}`, although each of its memories agrees on `{x}` with a
memory of `yz`: the identity `filter` compares the facts outside the key. -/
theorem identity_filter_no_inclusion :
    (eqDom FunMem).γ ((eqDom FunMem).filter [0] noFact) memYnZ ∧
    ¬ (eqDom FunMem).γ ((eqDom FunMem).filter [0] yz) memYnZ ∧
    ∀ m, (eqDom FunMem).γ noFact m →
      ∃ m', (eqDom FunMem).γ yz m' ∧ AgreeOn [0] m m' := by
  refine ⟨fun _ hp => by simp [noFact, eqDom] at hp, memYnZ_not_mem, ?_⟩
  intro m _
  obtain ⟨c, hon, hoff⟩ := FunMem.combinable [0] m memYZ
  refine ⟨c, ?_, hon.symm⟩
  intro p hp
  simp only [yz, List.mem_singleton] at hp
  subst hp
  refine ⟨.int 5, ?_, ?_⟩
  · exact (hoff 1 (by simp)).trans rfl
  · exact (hoff 2 (by simp)).trans rfl

/-! ## Non-emptiness cannot be dropped -/

/-- A stored input whose components hold `y ∈ {0}` and `y ∈ {1}`. -/
def emptyS : valueProd.State := ([(1, [.int 0])], [(1, [.int 1])])

/-- The counterexample. Both components meet `relate` sound and each covers
some memory, the key `{x}` is closed and `filter` decomposes the product on
it, but the product covers no memory and `filter` is not exact on `{x}`. -/
theorem nonempty_needed :
    (valueDom FunMem).RelateSound ∧
    (∃ w, (valueDom FunMem).γ emptyS.1 w) ∧
    (∃ w, (valueDom FunMem).γ emptyS.2 w) ∧
    valueProd.Closed [0] emptyS ∧ valueProd.Decomposes [0] emptyS ∧
    (¬ ∃ w, valueProd.γ emptyS w) ∧ ¬ valueProd.ExactOn [0] emptyS := by
  have hempty : ¬ ∃ w, valueProd.γ emptyS w := by
    rintro ⟨w, h₁, h₂⟩
    obtain ⟨v₁, hv₁, e₁⟩ := h₁ (1, [.int 0]) (by simp [emptyS])
    obtain ⟨v₂, hv₂, e₂⟩ := h₂ (1, [.int 1]) (by simp [emptyS])
    simp only [List.mem_singleton] at hv₁ hv₂
    subst hv₁ hv₂
    rw [e₁] at e₂
    cases e₂
  refine ⟨valueDom_relateSound, ⟨memOf [.int 0, .int 0], ?_⟩,
    ⟨memOf [.int 0, .int 1], ?_⟩,
    closed_prod_iff.mpr ⟨valueDom_closed _ _, valueDom_closed _ _⟩,
    decomposes_prod (valueDom_decomposes _ _) (valueDom_decomposes _ _),
    hempty, ?_⟩
  · intro p hp
    simp only [emptyS, List.mem_singleton] at hp
    subst hp
    exact ⟨_, List.mem_singleton_self _, rfl⟩
  · intro p hp
    simp only [emptyS, List.mem_singleton] at hp
    subst hp
    exact ⟨_, List.mem_singleton_self _, rfl⟩
  · intro hex
    have hf : valueProd.γ (valueProd.filter [0] emptyS) (memOf [.int 0]) := by
      refine ⟨?_, ?_⟩ <;> intro p hp <;> simp [prod, valueDom, emptyS] at hp
    obtain ⟨w, hw, -⟩ := hex _ hf
    exact hempty ⟨w, hw⟩

end Checks
