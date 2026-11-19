import ReuseModel.SideTables

namespace Checks

open ReuseModel.SideTables

/-- Each contract is exercised on an actual access. A changed read, a
write at the producer's position, and admission of unsupported nested work
all violate their respective contracts. -/
theorem side_table_contracts :
    KeyedRead (fun (_ : Unit) => True) (fun _ (_ : Unit) => True)
        (fun _ _ => true) (fun _ _ => true) ∧
    ¬ KeyedRead (fun (_ : Unit) => True) (fun _ (_ : Unit) => True)
        (fun _ _ => true) (fun _ _ => false) ∧
    FixedRead (fun (_ : Bool) (_ : Unit) => True) (fun _ _ => true) ∧
    ¬ FixedRead (fun (_ : Bool) (_ : Unit) => True) (fun t _ => t) ∧
    RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => true)
        (fun _ => true) (fun _ => true) (fun _ _ => false) (fun _ p => p) Bool.or ∧
    ¬ RecordedWrite (fun (_ : Unit) => True) (fun _ => True) (fun _ => true)
        (fun _ => true) (fun _ => true) (fun _ _ => false) (fun _ p => !p) Bool.or ∧
    UnsupportedAccess (fun (_ : Unit) => False) (fun (_ : Unit) => False)
        (fun _ (_ : Unit) => True) (fun _ _ => True) (fun _ => True) ∧
    ¬ UnsupportedAccess (fun (_ : Unit) => False) (fun (_ : Unit) => True)
        (fun _ (_ : Unit) => True) (fun _ _ => True) (fun _ => True) := by
  refine ⟨fun _ _ _ _ => rfl, ?_, fun _ _ _ _ _ => rfl, ?_, ?_, ?_, ?_, ?_⟩
  · intro h
    cases h () trivial () trivial
  · intro h
    cases h false true () trivial trivial
  · refine ⟨Bool.or_assoc, Bool.or_comm, Bool.or_self, fun _ _ _ => ⟨rfl, rfl, ?_⟩⟩
    intro p hp
    cases p
    · rfl
    · exact False.elim (hp rfl)
  · intro h
    cases (h.2.2.2 () trivial trivial).2.1
  · exact ⟨fun _ _ _ _ h => h, fun _ _ _ _ h => h⟩
  · exact fun h => h.2 () () trivial trivial trivial

end Checks
