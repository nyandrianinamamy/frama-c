import ReuseModel
import Checks.AxiomCheck

/-!
# Axioms of the theorems

`#print axioms` shows the axioms of each theorem in the build log.
`#check_axioms` fails the build if one of them depends on `sorryAx` or on an
axiom other than Lean's standard ones.
-/

#print axioms ReuseModel.frame_lemma
#print axioms ReuseModel.frame_of_not_written
#print axioms ReuseModel.steps_iff_run

#check_axioms ReuseModel.frame_lemma
#check_axioms ReuseModel.frame_of_not_written
#check_axioms ReuseModel.steps_iff_run

/-! The check rejects a theorem that depends on another axiom. `native_decide`
makes the proof depend on the axioms that trust the compiler. `#guard_msgs`
fails the build unless the check reports exactly this error. -/

namespace Checks

theorem viaCompiler : 2 + 2 = 4 := by native_decide

end Checks

/--
error: Checks.viaCompiler depends on axioms outside the standard ones: [Lean.ofReduceBool, Lean.trustCompiler]
-/
#guard_msgs in
#check_axioms Checks.viaCompiler
