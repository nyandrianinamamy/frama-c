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

/-- For each fixed observation, its value is invariant across positions in
the same run where it can be read. Positions may distinguish times. -/
def FixedRead {Time Read Value : Type} (reads : Time → Read → Prop)
    (observe : Time → Read → Value) : Prop :=
  ∀ t₁ t₂ read, reads t₁ read → reads t₂ read → observe t₁ read = observe t₂ read

/-- The saved contribution covers the fresh contribution and is joined into
the existing table at the current hit's position. The before/after tables
describe the replay of this contribution. The join laws allow repeated
replay of the same contribution at the same position. -/
def RecordedWrite {Hit Position Value : Type} (admitted writes : Hit → Prop)
    (position : Hit → Position) (fresh saved : Hit → Value)
    (before after : Hit → Position → Value) (join : Value → Value → Value) : Prop :=
  (∀ x y z, join (join x y) z = join x (join y z)) ∧
  (∀ x y, join x y = join y x) ∧ (∀ x, join x x = x) ∧
  ∀ hit, admitted hit → writes hit →
    join (fresh hit) (saved hit) = saved hit ∧
    after hit (position hit) = join (before hit (position hit)) (saved hit) ∧
    ∀ p, p ≠ position hit → after hit p = before hit p

/-- Unsupported accesses, including unclassified accesses and overwrites
without a separate justification, prevent storage and admission. The
access relations include both direct and skipped nested work. -/
def UnsupportedAccess {Entry Hit Access : Type} (stored : Entry → Prop)
    (admitted : Hit → Prop) (producerAccess : Entry → Access → Prop)
    (hitAccess : Hit → Access → Prop) (unsupported : Access → Prop) : Prop :=
  (∀ entry access, producerAccess entry access → unsupported access → ¬ stored entry) ∧
  (∀ hit access, hitAccess hit access → unsupported access → ¬ admitted hit)

end ReuseModel.SideTables
