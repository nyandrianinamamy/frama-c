import ReuseModel.Syntax

/-!
# Concrete memory

The semantics uses memory only through the interface `Memory`: access to the
value of a block, faults on blocks that are not live, and lifetime. The laws of
the interface are all that the theorems use, so they hold for every memory that
satisfies them. `FunMem` is one such memory, which shows that the laws can be
met.

A block is live from its creation until it is released. Identifiers are never
reused: a pointer to a released block stays dangling, and an access through it
faults. Releasing a block rewrites nothing else; in particular, blocks that
hold a pointer to it keep that pointer. The model has no sweep.
-/

namespace ReuseModel

/-- The concrete memory interface and its laws. -/
class Memory (M : Type) where
  /-- The value of a block, or `none` when the block is not live. -/
  load : M → Block → Option Value
  /-- Overwrite the value of a block. `none` is a fault: the block is not
  live. -/
  store : M → Block → Value → Option M
  /-- Create a block with an initial value. -/
  create : M → Value → Block × M
  /-- End the lifetime of a block. -/
  release : M → Block → M
  /-- The block has been created at some time, and may have been released
  since. -/
  Issued : M → Block → Prop
  issued_of_load : ∀ {m b v}, load m b = some v → Issued m b
  store_ok_iff : ∀ {m b v}, (store m b v).isSome = (load m b).isSome
  load_store_same : ∀ {m b v m'}, store m b v = some m' → load m' b = some v
  load_store_other : ∀ {m b v m' b'},
    store m b v = some m' → b' ≠ b → load m' b' = load m b'
  issued_store : ∀ {m b v m' b'}, store m b v = some m' → Issued m b' → Issued m' b'
  not_issued_create : ∀ m v, ¬ Issued m (create m v).1
  load_create_same : ∀ m v, load (create m v).2 (create m v).1 = some v
  load_create_other : ∀ m v b, b ≠ (create m v).1 →
    load (create m v).2 b = load m b
  issued_create : ∀ m v b, Issued m b → Issued (create m v).2 b
  load_release_same : ∀ m b, load (release m b) b = none
  load_release_other : ∀ m b b', b' ≠ b → load (release m b) b' = load m b'
  issued_release : ∀ m b b', Issued m b' → Issued (release m b) b'

open Memory

section
variable {M : Type} [Memory M]

/-- The block is live: it has a value. -/
def Live (m : M) (b : Block) : Prop := (load m b).isSome

theorem Live.issued {m : M} {b : Block} (h : Live m b) : Issued m b := by
  unfold Live at h
  cases hl : load m b with
  | none => rw [hl] at h; contradiction
  | some v => exact issued_of_load hl

/-- Create one block per value, in order. -/
def createAll (m : M) : List Value → List Block × M
  | [] => ([], m)
  | v :: vs =>
    let r₁ := create m v
    let r₂ := createAll r₁.2 vs
    (r₁.1 :: r₂.1, r₂.2)

/-- Release the blocks, in order. -/
def releaseAll (m : M) : List Block → M
  | [] => m
  | b :: bs => releaseAll (release m b) bs

/-- Creating blocks leaves an issued block unchanged, keeps it issued, and
never returns it. -/
theorem createAll_issued {m : M} {b : Block} (vs : List Value) (h : Issued m b) :
    load (createAll m vs).2 b = load m b ∧ Issued (createAll m vs).2 b ∧
      b ∉ (createAll m vs).1 := by
  induction vs generalizing m with
  | nil => exact ⟨rfl, h, by simp [createAll]⟩
  | cons v vs ih =>
    have hne : b ≠ (create m v).1 := by
      intro heq
      exact not_issued_create m v (heq ▸ h)
    obtain ⟨h₁, h₂, h₃⟩ := ih (issued_create m v b h)
    refine ⟨?_, h₂, ?_⟩
    · simp only [createAll]
      rw [h₁, load_create_other m v b hne]
    · simp only [createAll, List.mem_cons, not_or]
      exact ⟨hne, h₃⟩

/-- Releasing other blocks leaves a block unchanged and keeps it issued. -/
theorem releaseAll_other {m : M} {b : Block} (bs : List Block) (hb : b ∉ bs)
    (h : Issued m b) :
    load (releaseAll m bs) b = load m b ∧ Issued (releaseAll m bs) b := by
  induction bs generalizing m with
  | nil => exact ⟨rfl, h⟩
  | cons b' bs ih =>
    simp only [List.mem_cons, not_or] at hb
    obtain ⟨h₁, h₂⟩ := ih hb.2 (issued_release m b' b h)
    refine ⟨?_, h₂⟩
    simp only [releaseAll]
    rw [h₁, load_release_other m b' b hb.1]

end

/-! ## A memory that meets the laws -/

/-- Point update of the cells of a memory. -/
def updateCell (f : Block → Option Value) (b : Block) (v : Option Value) :
    Block → Option Value :=
  fun b' => if b' = b then v else f b'

/-- A memory as a function from blocks to optional values, with the next
identifier to issue. No block from `next` on has a value. -/
structure FunMem where
  cells : Block → Option Value
  next : Block
  fresh : ∀ b, next ≤ b → cells b = none

namespace FunMem

/-- The memory with no block. -/
def empty : FunMem where
  cells := fun _ => none
  next := 0
  fresh := fun _ _ => rfl

def store (m : FunMem) (b : Block) (v : Value) : Option FunMem :=
  if h : (m.cells b).isSome then
    some
      { cells := updateCell m.cells b (some v)
        next := m.next
        fresh := by
          intro b' hb'
          have hlt : b < m.next := by
            refine Nat.lt_of_not_le fun hle => ?_
            rw [m.fresh b hle] at h
            contradiction
          have hne : b' ≠ b := Nat.ne_of_gt (Nat.lt_of_lt_of_le hlt hb')
          simp [updateCell, hne, m.fresh b' hb'] }
  else none

def create (m : FunMem) (v : Value) : Block × FunMem :=
  (m.next,
    { cells := updateCell m.cells m.next (some v)
      next := m.next + 1
      fresh := by
        intro b' hb'
        have hne : b' ≠ m.next := Nat.ne_of_gt hb'
        simp [updateCell, hne, m.fresh b' (Nat.le_of_succ_le hb')] })

def release (m : FunMem) (b : Block) : FunMem where
  cells := updateCell m.cells b none
  next := m.next
  fresh := by
    intro b' hb'
    by_cases hne : b' = b
    · simp [updateCell, hne]
    · simp [updateCell, hne, m.fresh b' hb']

instance : Memory FunMem where
  load m b := m.cells b
  store := FunMem.store
  create := FunMem.create
  release := FunMem.release
  Issued m b := b < m.next
  issued_of_load := by
    intro m b v h
    refine Nat.lt_of_not_le fun hle => ?_
    rw [m.fresh b hle] at h
    contradiction
  store_ok_iff := by
    intro m b v
    unfold FunMem.store
    split <;> simp_all
  load_store_same := by
    intro m b v m' h
    unfold FunMem.store at h
    split at h
    · cases h; simp [updateCell]
    · contradiction
  load_store_other := by
    intro m b v m' b' h hne
    unfold FunMem.store at h
    split at h
    · cases h; simp [updateCell, hne]
    · contradiction
  issued_store := by
    intro m b v m' b' h hb
    unfold FunMem.store at h
    split at h
    · cases h; exact hb
    · contradiction
  not_issued_create := by
    intro m v
    simp [FunMem.create]
  load_create_same := by
    intro m v
    simp [FunMem.create, updateCell]
  load_create_other := by
    intro m v b hne
    simp [FunMem.create, updateCell] at hne ⊢
    simp [hne]
  issued_create := by
    intro m v b hb
    exact Nat.lt_succ_of_lt hb
  load_release_same := by
    intro m b
    simp [FunMem.release, updateCell]
  load_release_other := by
    intro m b b' hne
    simp [FunMem.release, updateCell, hne]
  issued_release := by
    intro m b b' hb
    exact hb

end FunMem

end ReuseModel
