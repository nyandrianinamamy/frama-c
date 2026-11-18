import ReuseModel
import Checks.AxiomCheck
import Checks.Domains

/-!
# Axioms of the theorems

`#print axioms` shows the axioms of each theorem in the build log.
`#check_axioms` fails the build if one of them depends on `sorryAx` or on an
axiom other than Lean's standard ones.
-/

#print axioms ReuseModel.frame_lemma
#print axioms ReuseModel.frame_of_not_written
#print axioms ReuseModel.steps_iff_run
#print axioms ReuseModel.WellFormed.stmt_labels_nodup
#print axioms ReuseModel.WellFormed.sub
#print axioms ReuseModel.WellFormed.body
#print axioms ReuseModel.FunMem.combinable
#print axioms ReuseModel.Domain.closed_prod_iff
#print axioms ReuseModel.Domain.decomposes_prod
#print axioms ReuseModel.Domain.filterSound_prod
#print axioms ReuseModel.Domain.relateSound_prod
#print axioms ReuseModel.Domain.reuseSound_prod
#print axioms ReuseModel.Domain.filterStrong_of_decomposes
#print axioms ReuseModel.Domain.exactOn_of_decomposes
#print axioms ReuseModel.Domain.filterExact_of_relateSound
#print axioms ReuseModel.Domain.match_lemma
#print axioms ReuseModel.Domain.product_lemma
#print axioms ReuseModel.Domain.projected_match

#check_axioms ReuseModel.frame_lemma
#check_axioms ReuseModel.frame_of_not_written
#check_axioms ReuseModel.steps_iff_run
#check_axioms ReuseModel.WellFormed.stmt_labels_nodup
#check_axioms ReuseModel.WellFormed.sub
#check_axioms ReuseModel.WellFormed.body
#check_axioms ReuseModel.FunMem.combinable
#check_axioms ReuseModel.Domain.closed_prod_iff
#check_axioms ReuseModel.Domain.decomposes_prod
#check_axioms ReuseModel.Domain.filterSound_prod
#check_axioms ReuseModel.Domain.relateSound_prod
#check_axioms ReuseModel.Domain.reuseSound_prod
#check_axioms ReuseModel.Domain.filterStrong_of_decomposes
#check_axioms ReuseModel.Domain.exactOn_of_decomposes
#check_axioms ReuseModel.Domain.filterExact_of_relateSound
#check_axioms ReuseModel.Domain.match_lemma
#check_axioms ReuseModel.Domain.product_lemma
#check_axioms ReuseModel.Domain.projected_match

/-! The domains that meet the laws and the negative cases, in
`Checks/Domains.lean`. -/

#print axioms Checks.valueDom_laws
#print axioms Checks.valueProd_match
#print axioms Checks.identity_filter_negative
#print axioms Checks.eqDom_not_relateSound
#print axioms Checks.eqDom_existing
#print axioms Checks.eqDom_reuseSound
#print axioms Checks.eqDom_not_closed_y
#print axioms Checks.identity_filter_no_inclusion
#print axioms Checks.nonempty_needed

#check_axioms Checks.valueDom_laws
#check_axioms Checks.valueProd_match
#check_axioms Checks.identity_filter_negative
#check_axioms Checks.eqDom_not_relateSound
#check_axioms Checks.eqDom_existing
#check_axioms Checks.eqDom_reuseSound
#check_axioms Checks.eqDom_not_closed_y
#check_axioms Checks.identity_filter_no_inclusion
#check_axioms Checks.nonempty_needed

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
