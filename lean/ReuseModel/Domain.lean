import ReuseModel.Memory

/-!
# Abstract domains, their laws, and the match

An abstract domain has states, a concretisation `γ` from states to sets of
memories, and the three operations of the cache: `filter`, `relate` and
`reuse`. The laws of a domain are stated on `γ`:

* `filter` sound, in its weak form: `filter` only forgets (`FilterSound`);
* `relate` sound: on a closed set, `filter` decomposes the state, and
  `relate` returns only blocks that exist in the state (`RelateSound`);
* `filter` exact on the stored input for a closed key (`FilterExact`);
* `reuse` sound: the result covers every memory that combines the written
  part of an output memory with the rest of a current memory (`ReuseSound`).

The product of two domains has the union of the two `relate` as its `relate`,
so that a set closed in the product is closed in both components.

The match lemma (`match_lemma`) puts each current concrete memory in the
filtered stored input, and gives a memory of the stored input that agrees
with it on the key. The product lemma (`product_lemma`) derives exactness on
a closed product key from the decomposition of each component, with
non-emptiness of the stored concretisation as a hypothesis.
`projected_match` composes the two. Neither lemma takes a hypothesis on the
current input other than weak `filter` soundness and the inclusion of the
filtered inputs.

Two memories agree on a set of blocks when each block of the set has the same
content (`Memory.load`) in both. The memory interface has no operation that
builds a memory from two others; the product lemma takes as a hypothesis that
such a memory exists (`Combinable`), and `FunMem` meets it.
-/

namespace ReuseModel

open Memory

/-- A finite set of blocks, given by a list. Only membership is used: the
order and the repetitions of the list do not matter. -/
abbrev BlockSet := List Block

section
variable {M : Type} [Memory M]

/-- `m` and `m'` agree on `B`: each block of `B` has the same content in
both. -/
def AgreeOn (B : BlockSet) (m m' : M) : Prop :=
  ∀ b ∈ B, load m b = load m' b

/-- `m` and `m'` agree outside `B`: each block that is not in `B` has the
same content in both. -/
def AgreeOff (B : BlockSet) (m m' : M) : Prop :=
  ∀ b, b ∉ B → load m b = load m' b

theorem AgreeOn.symm {B : BlockSet} {m m' : M} (h : AgreeOn B m m') :
    AgreeOn B m' m :=
  fun b hb => (h b hb).symm

theorem AgreeOn.trans {B : BlockSet} {m₁ m₂ m₃ : M}
    (h₁ : AgreeOn B m₁ m₂) (h₂ : AgreeOn B m₂ m₃) : AgreeOn B m₁ m₃ :=
  fun b hb => (h₁ b hb).trans (h₂ b hb)

end

/-- Two memories can be combined on any set of blocks: some memory agrees
with the first on the set and with the second outside it. -/
def Combinable (M : Type) [Memory M] : Prop :=
  ∀ (B : BlockSet) (m w : M), ∃ c, AgreeOn B c m ∧ AgreeOff B c w

/-- `FunMem` meets `Combinable`: take the cells of the first memory on the
set and those of the second outside it. -/
theorem FunMem.combinable : Combinable FunMem := by
  intro B m w
  refine ⟨{ cells := fun b => if b ∈ B then m.cells b else w.cells b
            next := max m.next w.next
            fresh := ?_ }, ?_, ?_⟩
  · intro b hb
    have hm := m.fresh b (Nat.le_trans (Nat.le_max_left _ _) hb)
    have hw := w.fresh b (Nat.le_trans (Nat.le_max_right _ _) hb)
    by_cases h : b ∈ B <;> simp [h, hm, hw]
  · intro b hb
    show (if b ∈ B then m.cells b else w.cells b) = m.cells b
    simp [hb]
  · intro b hb
    show (if b ∈ B then m.cells b else w.cells b) = w.cells b
    simp [hb]

/-! ## Domains and their laws -/

/-- An abstract domain on memories of type `M`. -/
structure Domain (M : Type) where
  /-- The abstract states. -/
  State : Type
  /-- The concretisation: `γ S m` holds when the state `S` covers the memory
  `m`. -/
  γ : State → M → Prop
  /-- `filter B S` keeps what `S` says about the blocks of `B`. -/
  filter : BlockSet → State → State
  /-- `relate B S` gives the blocks that `S` relates to those of `B`. `none`
  stands for `Top`. -/
  relate : BlockSet → State → Option BlockSet
  /-- `reuse W cur out` gives the state at the exit of a hit: the current
  input `cur` with the blocks of `W` taken from the stored output `out`. -/
  reuse : BlockSet → State → State → State

namespace Domain

variable {M : Type} [Memory M]

/-- `filter` sound, weak form: `filter` only forgets. The identity is an
instance. -/
def FilterSound (d : Domain M) : Prop :=
  ∀ B S m, d.γ S m → d.γ (d.filter B S) m

/-- `B` is closed in `S`: `relate B S` is not `Top` and returns only blocks of
`B`. -/
def Closed (d : Domain M) (B : BlockSet) (S : d.State) : Prop :=
  ∃ R, d.relate B S = some R ∧ ∀ b ∈ R, b ∈ B

/-- `filter` decomposes `S` on `B`. -/
structure Decomposes (d : Domain M) (B : BlockSet) (S : d.State) : Prop where
  /-- Membership in `γ (filter B S)` depends only on the blocks of `B`. -/
  onKey : ∀ m m', AgreeOn B m m' → d.γ (d.filter B S) m →
    d.γ (d.filter B S) m'
  /-- `γ S` is the set of memories of `γ (filter B S)` that agree outside `B`
  with a memory of `γ S`. -/
  split : ∀ m, d.γ S m ↔
    d.γ (d.filter B S) m ∧ ∃ w, d.γ S w ∧ AgreeOff B m w

/-- `relate` sound: on a closed set, `filter` decomposes the state, and
`relate` returns only blocks that exist in the state, that is blocks live in
every memory that the state covers. -/
structure RelateSound (d : Domain M) : Prop where
  /-- On a closed set, `filter` decomposes the state. -/
  decomposes : ∀ B S, d.Closed B S → d.Decomposes B S
  /-- `relate` returns only blocks that exist in the state. -/
  existing : ∀ B S R, d.relate B S = some R →
    ∀ b ∈ R, ∀ m, d.γ S m → Live m b

/-- `filter` is exact on `S` for the key `K`: each memory of
`γ (filter K S)` agrees on `K` with a memory of `γ S`. -/
def ExactOn (d : Domain M) (K : BlockSet) (S : d.State) : Prop :=
  ∀ m, d.γ (d.filter K S) m → ∃ m', d.γ S m' ∧ AgreeOn K m m'

/-- `filter` exact, as a law: on every state with a non-empty concretisation,
for every key closed in it. It is required of the stored input. -/
def FilterExact (d : Domain M) : Prop :=
  ∀ K S, d.Closed K S → (∃ w, d.γ S w) → d.ExactOn K S

/-- `reuse` sound: `γ (reuse W cur out)` contains every memory that agrees on
`W` with a memory of `γ out` and outside `W` with a memory of `γ cur`, whether
or not that whole memory is in `γ out`. -/
def ReuseSound (d : Domain M) : Prop :=
  ∀ W cur out (mc mo c : M), d.γ cur mc → d.γ out mo →
    AgreeOn W c mo → AgreeOff W c mc → d.γ (d.reuse W cur out) c

/-! ## Product -/

/-- The product of two domains. A memory is covered by a pair of states when
each component covers it. `filter` and `reuse` work componentwise; `relate`
is the union of the two results, `Top` when either is `Top`. -/
def prod (d₁ d₂ : Domain M) : Domain M where
  State := d₁.State × d₂.State
  γ S m := d₁.γ S.1 m ∧ d₂.γ S.2 m
  filter B S := (d₁.filter B S.1, d₂.filter B S.2)
  relate B S :=
    match d₁.relate B S.1, d₂.relate B S.2 with
    | some R₁, some R₂ => some (R₁ ++ R₂)
    | _, _ => none
  reuse W cur out := (d₁.reuse W cur.1 out.1, d₂.reuse W cur.2 out.2)

omit [Memory M] in
/-- A set is closed in the product exactly when it is closed in both
components. -/
theorem closed_prod_iff {d₁ d₂ : Domain M} {B : BlockSet}
    {S : (d₁.prod d₂).State} :
    (d₁.prod d₂).Closed B S ↔ d₁.Closed B S.1 ∧ d₂.Closed B S.2 := by
  simp only [Closed, prod]
  constructor
  · rintro ⟨R, hR, hsub⟩
    split at hR
    · next R₁ R₂ h₁ h₂ =>
      cases hR
      exact ⟨⟨R₁, h₁, fun b hb => hsub b (List.mem_append_left _ hb)⟩,
        ⟨R₂, h₂, fun b hb => hsub b (List.mem_append_right _ hb)⟩⟩
    · cases hR
  · rintro ⟨⟨R₁, h₁, hs₁⟩, ⟨R₂, h₂, hs₂⟩⟩
    refine ⟨R₁ ++ R₂, by simp [h₁, h₂], fun b hb => ?_⟩
    rcases List.mem_append.mp hb with hb | hb
    · exact hs₁ b hb
    · exact hs₂ b hb

/-- The product decomposes on `B` when both components do. Neither closure
nor non-emptiness is used. -/
theorem decomposes_prod {d₁ d₂ : Domain M} {B : BlockSet}
    {S : (d₁.prod d₂).State} (h₁ : d₁.Decomposes B S.1)
    (h₂ : d₂.Decomposes B S.2) : (d₁.prod d₂).Decomposes B S where
  onKey m m' hag hm :=
    ⟨h₁.onKey m m' hag hm.1, h₂.onKey m m' hag hm.2⟩
  split m := by
    constructor
    · intro hm
      exact ⟨⟨((h₁.split m).mp hm.1).1, ((h₂.split m).mp hm.2).1⟩,
        m, hm, fun _ _ => rfl⟩
    · rintro ⟨hf, w, hw, hoff⟩
      exact ⟨(h₁.split m).mpr ⟨hf.1, w, hw.1, hoff⟩,
        (h₂.split m).mpr ⟨hf.2, w, hw.2, hoff⟩⟩

omit [Memory M] in
theorem filterSound_prod {d₁ d₂ : Domain M} (h₁ : d₁.FilterSound)
    (h₂ : d₂.FilterSound) : (d₁.prod d₂).FilterSound :=
  fun B S m hm => ⟨h₁ B S.1 m hm.1, h₂ B S.2 m hm.2⟩

/-- The product meets `relate` sound when both components do: closure under
the union of the two `relate` gives closure in each component. -/
theorem relateSound_prod {d₁ d₂ : Domain M} (h₁ : d₁.RelateSound)
    (h₂ : d₂.RelateSound) : (d₁.prod d₂).RelateSound where
  decomposes B S hc :=
    have hc' := closed_prod_iff.mp hc
    decomposes_prod (h₁.decomposes B S.1 hc'.1) (h₂.decomposes B S.2 hc'.2)
  existing B S R hR b hb m hm := by
    simp only [prod] at hR hm
    split at hR
    · next R₁ R₂ e₁ e₂ =>
      cases hR
      rcases List.mem_append.mp hb with hb | hb
      · exact h₁.existing B S.1 R₁ e₁ b hb m hm.1
      · exact h₂.existing B S.2 R₂ e₂ b hb m hm.2
    · cases hR

theorem reuseSound_prod {d₁ d₂ : Domain M} (h₁ : d₁.ReuseSound)
    (h₂ : d₂.ReuseSound) : (d₁.prod d₂).ReuseSound :=
  fun W cur out mc mo c hc ho hon hoff =>
    ⟨h₁ W cur.1 out.1 mc mo c hc.1 ho.1 hon hoff,
      h₂ W cur.2 out.2 mc mo c hc.2 ho.2 hon hoff⟩

/-! ## Exactness from decomposition -/

/-- Decomposition and a non-empty concretisation give exactness on the key:
a memory of `γ (filter K S)`, combined on `K` with a memory of `γ S`, is in
`γ S`. -/
theorem exactOn_of_decomposes {d : Domain M} {K : BlockSet} {S : d.State}
    (hc : Combinable M) (hd : d.Decomposes K S) (hne : ∃ w, d.γ S w) :
    d.ExactOn K S := by
  intro m hm
  obtain ⟨w, hw⟩ := hne
  obtain ⟨c, hon, hoff⟩ := hc K m w
  have hcf : d.γ (d.filter K S) c := hd.onKey m c (hon.symm) hm
  exact ⟨c, (hd.split c).mpr ⟨hcf, w, hw, hoff⟩, hon.symm⟩

/-- `filter` exact follows from `relate` sound. -/
theorem filterExact_of_relateSound {d : Domain M} (hc : Combinable M)
    (hr : d.RelateSound) : d.FilterExact :=
  fun _ _ hK hne => exactOn_of_decomposes hc (hr.decomposes _ _ hK) hne

/-! ## The match and product lemmas -/

/-- The product lemma: on a key closed in the stored input `S` of a product,
`filter` is exact when each component meets `relate` sound and the
concretisation of `S` is not empty. Closure is required in `S` only. The
components need not meet `filter` exact: exactness of the product is derived
from the decomposition of each component. -/
theorem product_lemma {d₁ d₂ : Domain M} {K : BlockSet}
    {S : (d₁.prod d₂).State} (hc : Combinable M) (h₁ : d₁.RelateSound)
    (h₂ : d₂.RelateSound) (hK : (d₁.prod d₂).Closed K S)
    (hne : ∃ w, (d₁.prod d₂).γ S w) : (d₁.prod d₂).ExactOn K S :=
  exactOn_of_decomposes hc ((relateSound_prod h₁ h₂).decomposes K S hK) hne

/-- The match lemma. Weak `filter` soundness on the current input `C` and the
inclusion of the filtered current input in the filtered stored input put each
memory of `γ C` in the filtered stored input. Exactness of `filter` on the
stored input `S` then gives a memory of `γ S` that agrees with it on the
key. -/
theorem match_lemma {d : Domain M} {K : BlockSet} {C S : d.State}
    (hsound : ∀ m, d.γ C m → d.γ (d.filter K C) m)
    (hincl : ∀ m, d.γ (d.filter K C) m → d.γ (d.filter K S) m)
    (hexact : d.ExactOn K S) {m : M} (hm : d.γ C m) :
    d.γ (d.filter K S) m ∧ ∃ m', d.γ S m' ∧ AgreeOn K m m' :=
  have hf := hincl m (hsound m hm)
  ⟨hf, hexact m hf⟩

/-- The match on a product, from the laws of its components: the match lemma
with the exactness given by the product lemma. The key is closed in the
stored input `S`; nothing is required of the current input `C` beyond
`filter` sound and the inclusion of the filtered inputs. -/
theorem projected_match {d₁ d₂ : Domain M} {K : BlockSet}
    {C S : (d₁.prod d₂).State} (hc : Combinable M)
    (hf₁ : d₁.FilterSound) (hf₂ : d₂.FilterSound)
    (h₁ : d₁.RelateSound) (h₂ : d₂.RelateSound)
    (hK : (d₁.prod d₂).Closed K S) (hne : ∃ w, (d₁.prod d₂).γ S w)
    (hincl : ∀ m, (d₁.prod d₂).γ ((d₁.prod d₂).filter K C) m →
      (d₁.prod d₂).γ ((d₁.prod d₂).filter K S) m)
    {m : M} (hm : (d₁.prod d₂).γ C m) :
    ∃ m', (d₁.prod d₂).γ S m' ∧ AgreeOn K m m' :=
  (match_lemma (fun m' hm' => filterSound_prod hf₁ hf₂ K C m' hm') hincl
    (product_lemma hc h₁ h₂ hK hne) hm).2

end Domain

end ReuseModel
