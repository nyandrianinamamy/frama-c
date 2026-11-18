import Lean

/-!
# Axiom check

`#check_axioms d` reports the axioms that the declaration `d` depends on, and
fails unless all of them are among Lean's standard axioms `propext`,
`Classical.choice` and `Quot.sound`. It fails on `sorryAx` and on any other
axiom.
-/

namespace Checks

open Lean Elab Command

/-- The axioms that a theorem of the model may depend on. -/
def standardAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

/-- Report the axioms of a declaration; fail on an axiom outside
`standardAxioms`. -/
elab "#check_axioms " id:ident : command => do
  let n ← liftCoreM <| realizeGlobalConstNoOverloadWithInfo id
  let axs ← liftCoreM <| collectAxioms n
  let other := axs.filter fun a => !standardAxioms.contains a
  if other.isEmpty then
    logInfo m!"{n}: standard axioms only: {axs.toList}"
  else
    throwError m!"{n} depends on axioms outside the standard ones: {other.toList}"

end Checks
