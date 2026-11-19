/-!
# Side-table obligations for skipped work

These contracts range over a single run. The access relations must include
the transitive work skipped by the unit, including nested calls. A position
can be a callstack, another result index, or the unique position of an
unindexed table. The model does not classify Eva's tables.
-/

namespace ReuseModel.SideTables

/-- The saved observation for every keyed read is equal to the observation
at an admitted lookup, at the corresponding read site in the skipped work.
The relation selects each observation instance, including repeated reads. -/
def KeyedRead {Hit Read Value : Type} (admitted : Hit → Prop)
    (reads : Hit → Read → Prop) (saved lookup : Hit → Read → Value) : Prop :=
  ∀ hit, admitted hit → ∀ read, reads hit read → saved hit read = lookup hit read

/-- Each fixed observation has the same value at every time in the run. -/
def FixedRead {Time Read Value : Type} (observe : Time → Read → Value) : Prop :=
  ∀ t₁ t₂ read, observe t₁ read = observe t₂ read

/-- Run-wide invariance implies agreement at any two reported reads. -/
theorem FixedRead.agrees_on_reads {Time Read Value : Type}
    {observe : Time → Read → Value} (h : FixedRead observe)
    (reads : Time → Read → Prop) :
    ∀ t₁ t₂ read, reads t₁ read → reads t₂ read → observe t₁ read = observe t₂ read :=
  fun t₁ t₂ read _ _ => h t₁ t₂ read

/-- Every observation represented by the contribution is represented by the value. -/
def Covers {Value Observation : Type} (represents : Value → Observation → Prop)
    (value contribution : Value) : Prop :=
  ∀ o, represents contribution o → represents value o

/-- Join the payload into the table at the current hit position. Replay
covers the skipped execution's contribution and the previous contents
there, and preserves the represented observations at every other position.
The join covers both operands and supports repeated replay. -/
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

/-- Unsupported accesses, including unclassified accesses and overwrites
without a separate justification, prevent storage and admission. The
access relations include both direct and skipped nested work. -/
def UnsupportedAccess {Entry Hit Access : Type} (stored : Entry → Prop)
    (admitted : Hit → Prop) (producerAccess : Entry → Access → Prop)
    (hitAccess : Hit → Access → Prop) (unsupported : Access → Prop) : Prop :=
  (∀ entry access, producerAccess entry access → unsupported access → ¬ stored entry) ∧
  (∀ hit access, hitAccess hit access → unsupported access → ¬ admitted hit)

end ReuseModel.SideTables
