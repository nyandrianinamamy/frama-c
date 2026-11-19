import ReuseModel.SideTables

namespace Checks

open ReuseModel.SideTables

private theorem or_covers (x y : Bool) :
    Covers (fun v (_ : Unit) => v = true) (x || y) x ∧
    Covers (fun v (_ : Unit) => v = true) (x || y) y := by
  constructor
  · intro _ h
    simp [h]
  · intro _ h
    simp [h]

/-- Each contract is exercised on an actual access. The recorded write
makes its contribution at the hit position. -/
theorem side_table_contracts :
    KeyedRead (fun (_ : Unit) => True) (fun _ (_ : Unit) => True)
        (fun _ _ => true) (fun _ _ => true) ∧
    ¬ KeyedRead (fun (_ : Unit) => True) (fun _ (_ : Unit) => True)
        (fun _ _ => true) (fun _ _ => false) ∧
    FixedRead (fun (_ : Bool) (_ : Unit) => true) ∧
    RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => true)
        (fun _ => true) (fun _ => true) (fun _ _ => false) (fun _ p => p)
        Bool.or (fun v (_ : Unit) => v = true) ∧
    ¬ RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => true)
        (fun _ => true) (fun _ => true) (fun _ _ => false) (fun _ p => !p)
        Bool.or (fun v (_ : Unit) => v = true) ∧
    UnsupportedAccess (fun (_ : Unit) => False) (fun (_ : Unit) => False)
        (fun _ (_ : Unit) => True) (fun _ _ => True) (fun _ => True) ∧
    ¬ UnsupportedAccess (fun (_ : Unit) => False) (fun (_ : Unit) => True)
        (fun _ (_ : Unit) => True) (fun _ _ => True) (fun _ => True) := by
  refine ⟨fun _ _ _ _ => rfl, ?_, fun _ _ _ => rfl, ?_, ?_, ?_, ?_⟩
  · intro h
    cases h () trivial () trivial
  · refine ⟨Bool.or_assoc, Bool.or_comm, Bool.or_self, or_covers,
      fun _ _ _ => ⟨rfl, fun _ _ => rfl, fun _ _ => rfl, ?_⟩⟩
    intro p hp _
    cases p
    · rfl
    · exact False.elim (hp rfl)
  · intro h
    cases (h.2.2.2.2 () trivial trivial).1
  · simp [UnsupportedAccess]
  · exact fun h => h.2 () () trivial trivial trivial

/-- Agreement at reported reads can miss a change at an unobserved time. -/
theorem fixed_read_needs_run_invariance :
    (∀ t₁ t₂ : Bool, t₁ = false → t₂ = false → t₁ = t₂) ∧
    ¬ FixedRead (fun (t : Bool) (_ : Unit) => t) := by
  refine ⟨fun _ _ h₁ h₂ => h₁.trans h₂.symm, ?_⟩
  intro h
  cases h false true ()

/-- A collector reporting only the direct read can satisfy the contract
while the saved observation differs at the omitted nested read. -/
theorem keyed_read_can_miss_nested_read :
    let reads := fun (_ : Unit) (nested : Bool) => nested = false
    let saved := fun (_ : Unit) (_ : Bool) => false
    let lookup := fun (_ : Unit) (nested : Bool) => nested
    KeyedRead (fun _ => True) reads saved lookup ∧
      ¬ reads () true ∧ saved () true ≠ lookup () true := by
  exact ⟨fun _ _ _ h => h.symm, by decide, by decide⟩

/-- True represents that the site was reached. OR preserves the existing
and fresh reach contribution even with an empty payload. AND loses it. -/
theorem recorded_write_preserves_current_reach :
    RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => ())
        (fun _ => true) (fun _ => false) (fun _ _ => true) (fun _ _ => true)
        Bool.or (fun v (_ : Unit) => v = true) ∧
    ¬ RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => ())
        (fun _ => true) (fun _ => false) (fun _ _ => true) (fun _ _ => false)
        Bool.and (fun v (_ : Unit) => v = true) := by
  constructor
  · refine ⟨Bool.or_assoc, Bool.or_comm, Bool.or_self, or_covers,
      fun _ _ _ => ⟨rfl, fun _ _ => rfl, fun _ _ => rfl, ?_⟩⟩
    rintro ⟨⟩ hp
    exact (hp rfl).elim
  · intro h
    cases (h.2.2.2.1 true false).1 () rfl

/-- Neither the existing table nor the payload records the fresh reach
contribution, so performing the join still gives an unsound replay. -/
theorem recorded_write_needs_fresh_coverage :
    ¬ RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => ())
        (fun _ => true) (fun _ => false) (fun _ _ => false) (fun _ _ => false)
        Bool.or (fun v (_ : Unit) => v = true) := by
  intro h
  cases (h.2.2.2.2 () trivial trivial).2.2.1 () rfl

/-- The hit at true is correct, but replay erased the reach recorded at false. -/
theorem recorded_write_preserves_other_positions :
    ¬ RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => true)
        (fun _ => true) (fun _ => true) (fun _ p => !p) (fun _ p => p)
        Bool.or (fun v (_ : Unit) => v = true) := by
  intro h
  cases ((h.2.2.2.2 () trivial trivial).2.2.2 false (by decide) ()).mpr rfl

/-- The producer cannot store the entry even if no lookup is admitted. -/
theorem unsupported_producer_prevents_storage :
    ¬ UnsupportedAccess (fun (_ : Unit) => True) (fun (_ : Unit) => False)
        (fun _ (_ : Unit) => True) (fun _ _ => False) (fun _ => True) :=
  fun h => h.1 () () trivial trivial trivial

end Checks
