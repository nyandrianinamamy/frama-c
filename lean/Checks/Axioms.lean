import ReuseModel
import Checks.AxiomCheck
import Checks.Domains
import Checks.Entries
import Checks.Sweeps
import Checks.Inner
import Checks.Hit
import Checks.SideTables

/-!
# Axioms of the theorems

`#print axioms` shows the axioms of each theorem in the build log.
`#check_axioms` fails the build if one of them depends on `sorryAx` or on an
axiom other than Lean's standard ones.
-/

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
#print axioms ReuseModel.Domain.extensional_prod
#print axioms ReuseModel.Domain.closed_congr
#print axioms ReuseModel.Domain.decomposes_congr
#print axioms ReuseModel.Domain.exactOn_congr
#print axioms ReuseModel.Domain.filterStrong_of_decomposes
#print axioms ReuseModel.Domain.exactOn_of_decomposes
#print axioms ReuseModel.Domain.filterExact_of_relateSound
#print axioms ReuseModel.Domain.match_filtered
#print axioms ReuseModel.Domain.match_lemma
#print axioms ReuseModel.Domain.product_lemma
#print axioms ReuseModel.Domain.projected_match

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
#check_axioms ReuseModel.Domain.extensional_prod
#check_axioms ReuseModel.Domain.closed_congr
#check_axioms ReuseModel.Domain.decomposes_congr
#check_axioms ReuseModel.Domain.exactOn_congr
#check_axioms ReuseModel.Domain.filterStrong_of_decomposes
#check_axioms ReuseModel.Domain.exactOn_of_decomposes
#check_axioms ReuseModel.Domain.filterExact_of_relateSound
#check_axioms ReuseModel.Domain.match_filtered
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
#print axioms Checks.eqDom_extensional
#print axioms Checks.eqDom_not_closed_y
#print axioms Checks.eqDom_closed_x_dup
#print axioms Checks.identity_filter_no_inclusion
#print axioms Checks.nonempty_needed
#print axioms Checks.identity_filter_laws
#print axioms Checks.closed_needs_extensional

#check_axioms Checks.valueDom_laws
#check_axioms Checks.valueProd_match
#check_axioms Checks.identity_filter_negative
#check_axioms Checks.eqDom_not_relateSound
#check_axioms Checks.eqDom_existing
#check_axioms Checks.eqDom_reuseSound
#check_axioms Checks.eqDom_extensional
#check_axioms Checks.eqDom_not_closed_y
#check_axioms Checks.eqDom_closed_x_dup
#check_axioms Checks.identity_filter_no_inclusion
#check_axioms Checks.nonempty_needed
#check_axioms Checks.identity_filter_laws
#check_axioms Checks.closed_needs_extensional

/-! Entry construction and its examples, in `Checks/Entries.lean`. -/

section
open ReuseModel Checks

#check @ReuseModel.AllocatorAgreement.refl
#check @ReuseModel.FunMem.allocatorAgreement
#check @ReuseModel.ReplayAgreement.refl
#check @ReuseModel.CacheEntry.matches_of_input
#check @ReuseModel.writeTargets
#check @ReuseModel.run_agree_on_writes
#check @Checks.shorterInput
#check @Checks.projected_match_no_replay_witness
#check @Checks.deadDestination
#check @Checks.dead_destination_no_match
#check @Checks.nonpointer_load_reads_only_pointer
#check @ReuseModel.CacheEntry.sound_of_producer
#check @ReuseModel.run_agree
#check @ReuseModel.assertionHolds_agree
#check @Checks.load_overwrite_entry
#check @Checks.assert_before_overwrite
#check @Checks.missing_pointee_rejected
#check @Checks.allocator_needed
#check @Checks.prefix_writes_can_exceed_exit_writes

end

#print axioms ReuseModel.AllocatorAgreement.refl
#print axioms ReuseModel.FunMem.allocatorAgreement
#print axioms ReuseModel.ReplayAgreement.refl
#print axioms ReuseModel.CacheEntry.matches_of_input
#print axioms ReuseModel.writeTargets
#print axioms ReuseModel.run_agree_on_writes
#print axioms Checks.shorterInput
#print axioms Checks.projected_match_no_replay_witness
#print axioms Checks.deadDestination
#print axioms Checks.dead_destination_no_match
#print axioms Checks.nonpointer_load_reads_only_pointer
#print axioms ReuseModel.CacheEntry.sound_of_producer
#print axioms ReuseModel.run_agree
#print axioms ReuseModel.assertionHolds_agree
#print axioms Checks.load_overwrite_entry
#print axioms Checks.assert_before_overwrite
#print axioms Checks.missing_pointee_rejected
#print axioms Checks.allocator_needed
#print axioms Checks.prefix_writes_can_exceed_exit_writes

#check_axioms ReuseModel.AllocatorAgreement.refl
#check_axioms ReuseModel.FunMem.allocatorAgreement
#check_axioms ReuseModel.ReplayAgreement.refl
#check_axioms ReuseModel.CacheEntry.matches_of_input
#check_axioms ReuseModel.writeTargets
#check_axioms ReuseModel.run_agree_on_writes
#check_axioms Checks.shorterInput
#check_axioms Checks.projected_match_no_replay_witness
#check_axioms Checks.deadDestination
#check_axioms Checks.dead_destination_no_match
#check_axioms Checks.nonpointer_load_reads_only_pointer
#check_axioms ReuseModel.CacheEntry.sound_of_producer
#check_axioms ReuseModel.run_agree
#check_axioms ReuseModel.assertionHolds_agree
#check_axioms Checks.load_overwrite_entry
#check_axioms Checks.assert_before_overwrite
#check_axioms Checks.missing_pointee_rejected
#check_axioms Checks.allocator_needed
#check_axioms Checks.prefix_writes_can_exceed_exit_writes

/-! Lexical sweeps and the frame. -/

section
open ReuseModel

#check @ReuseModel.Value.escape
#print axioms ReuseModel.Value.escape
#check_axioms ReuseModel.Value.escape

#check @ReuseModel.Memory.sweep
#print axioms ReuseModel.Memory.sweep
#check_axioms ReuseModel.Memory.sweep

#check @ReuseModel.Memory.load_sweep_same
#print axioms ReuseModel.Memory.load_sweep_same
#check_axioms ReuseModel.Memory.load_sweep_same

#check @ReuseModel.Memory.load_sweep_other
#print axioms ReuseModel.Memory.load_sweep_other
#check_axioms ReuseModel.Memory.load_sweep_other

#check @ReuseModel.Memory.issued_sweep
#print axioms ReuseModel.Memory.issued_sweep
#check_axioms ReuseModel.Memory.issued_sweep

#check @ReuseModel.sweepAll
#print axioms ReuseModel.sweepAll
#check_axioms ReuseModel.sweepAll

#check @ReuseModel.applySweeps
#print axioms ReuseModel.applySweeps
#check_axioms ReuseModel.applySweeps

#check @ReuseModel.sweepTargets
#print axioms ReuseModel.sweepTargets
#check_axioms ReuseModel.sweepTargets

#check @ReuseModel.stepNext
#print axioms ReuseModel.stepNext
#check_axioms ReuseModel.stepNext

#check @ReuseModel.AllocatorAgreement.sweep
#print axioms ReuseModel.AllocatorAgreement.sweep
#check_axioms ReuseModel.AllocatorAgreement.sweep

#check @ReuseModel.frame_of_not_written
#print axioms ReuseModel.frame_of_not_written
#check_axioms ReuseModel.frame_of_not_written

#check @ReuseModel.frame_lemma
#print axioms ReuseModel.frame_lemma
#check_axioms ReuseModel.frame_lemma

#check @ReuseModel.sweep_target_fresh
#print axioms ReuseModel.sweep_target_fresh
#check_axioms ReuseModel.sweep_target_fresh

#check @ReuseModel.applySweeps_eq_iff
#print axioms ReuseModel.applySweeps_eq_iff
#check_axioms ReuseModel.applySweeps_eq_iff

#check @ReuseModel.frame_no_sweep_rewrite
#print axioms ReuseModel.frame_no_sweep_rewrite
#check_axioms ReuseModel.frame_no_sweep_rewrite

#check @Checks.own_local_sweep
#print axioms Checks.own_local_sweep
#check_axioms Checks.own_local_sweep

#check @Checks.own_local_frame_unchanged
#print axioms Checks.own_local_frame_unchanged
#check_axioms Checks.own_local_frame_unchanged

#check @Checks.future_pointer_needs_rewrite
#print axioms Checks.future_pointer_needs_rewrite
#check_axioms Checks.future_pointer_needs_rewrite

#check @Checks.return_sweeps_local
#print axioms Checks.return_sweeps_local
#check_axioms Checks.return_sweeps_local

#check @Checks.matching_frame_holder_rewritten
#print axioms Checks.matching_frame_holder_rewritten
#check_axioms Checks.matching_frame_holder_rewritten

#check @Checks.swept_holder_comparison_returns
#print axioms Checks.swept_holder_comparison_returns
#check_axioms Checks.swept_holder_comparison_returns

#check @Checks.nested_scope_sweep_in_caller
#print axioms Checks.nested_scope_sweep_in_caller
#check_axioms Checks.nested_scope_sweep_in_caller

end

/-! Shared Inner. -/

section
open ReuseModel

#check @ReuseModel.CacheEntry.InnerSound
#print axioms ReuseModel.CacheEntry.InnerSound
#check_axioms ReuseModel.CacheEntry.InnerSound

#check @ReuseModel.CacheEntry.shared_inner
#print axioms ReuseModel.CacheEntry.shared_inner
#check_axioms ReuseModel.CacheEntry.shared_inner

#check @Checks.loop_entry_premises
#print axioms Checks.loop_entry_premises
#check_axioms Checks.loop_entry_premises

#check @Checks.loop_member_matches
#print axioms Checks.loop_member_matches
#check_axioms Checks.loop_member_matches

#check @Checks.loop_shared_inner
#print axioms Checks.loop_shared_inner
#check_axioms Checks.loop_shared_inner

#check @Checks.loop_inner_outside_key
#print axioms Checks.loop_inner_outside_key
#check_axioms Checks.loop_inner_outside_key

#check @Checks.loop_first_visit_insufficient
#print axioms Checks.loop_first_visit_insufficient
#check_axioms Checks.loop_first_visit_insufficient

#check @Checks.fresh_local_must_be_keyed
#print axioms Checks.fresh_local_must_be_keyed
#check_axioms Checks.fresh_local_must_be_keyed

end

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

-- Within-analysis hit, its instance, and the side-table contracts.
section
open ReuseModel ReuseModel.SideTables Checks

#check @Domain.ReuseSoundAt
#print axioms ReuseModel.Domain.ReuseSoundAt
#check_axioms ReuseModel.Domain.ReuseSoundAt

#check @Domain.ReuseSound
#print axioms ReuseModel.Domain.ReuseSound
#check_axioms ReuseModel.Domain.ReuseSound
#check @exit_preserves_absence
#print axioms ReuseModel.exit_preserves_absence
#check_axioms ReuseModel.exit_preserves_absence

#check @CacheEntry.ReplayCompatible
#print axioms ReuseModel.CacheEntry.ReplayCompatible
#check_axioms ReuseModel.CacheEntry.ReplayCompatible

#check @CacheEntry.matches_of_projected
#print axioms ReuseModel.CacheEntry.matches_of_projected
#check_axioms ReuseModel.CacheEntry.matches_of_projected

#check @CacheEntry.replayCompatible_iff_matches
#print axioms ReuseModel.CacheEntry.replayCompatible_iff_matches
#check_axioms ReuseModel.CacheEntry.replayCompatible_iff_matches

#check @CacheEntry.NoFrameRewrite
#print axioms ReuseModel.CacheEntry.NoFrameRewrite
#check_axioms ReuseModel.CacheEntry.NoFrameRewrite

#check @CacheEntry.exit_frame_iff
#print axioms ReuseModel.CacheEntry.exit_frame_iff
#check_axioms ReuseModel.CacheEntry.exit_frame_iff

#check @CacheEntry.HitObservations
#print axioms ReuseModel.CacheEntry.HitObservations
#check_axioms ReuseModel.CacheEntry.HitObservations

#check @CacheEntry.HitObservations.exit
#print axioms ReuseModel.CacheEntry.HitObservations.exit
#check_axioms ReuseModel.CacheEntry.HitObservations.exit

#check @CacheEntry.HitObservations.reach
#print axioms ReuseModel.CacheEntry.HitObservations.reach
#check_axioms ReuseModel.CacheEntry.HitObservations.reach

#check @CacheEntry.HitObservations.safety
#print axioms ReuseModel.CacheEntry.HitObservations.safety
#check_axioms ReuseModel.CacheEntry.HitObservations.safety

#check @CacheEntry.HitObservations.valid
#print axioms ReuseModel.CacheEntry.HitObservations.valid
#check_axioms ReuseModel.CacheEntry.HitObservations.valid

#check @CacheEntry.hit_of_matches
#print axioms ReuseModel.CacheEntry.hit_of_matches
#check_axioms ReuseModel.CacheEntry.hit_of_matches

#check @CacheEntry.hit
#print axioms ReuseModel.CacheEntry.hit
#check_axioms ReuseModel.CacheEntry.hit

#check @KeyedRead
#print axioms ReuseModel.SideTables.KeyedRead
#check_axioms ReuseModel.SideTables.KeyedRead

#check @FixedRead
#print axioms ReuseModel.SideTables.FixedRead
#check_axioms ReuseModel.SideTables.FixedRead

#check @FixedRead.agrees_on_reads
#print axioms ReuseModel.SideTables.FixedRead.agrees_on_reads
#check_axioms ReuseModel.SideTables.FixedRead.agrees_on_reads

#check @Covers
#print axioms ReuseModel.SideTables.Covers
#check_axioms ReuseModel.SideTables.Covers

#check @RecordedWrite
#print axioms ReuseModel.SideTables.RecordedWrite
#check_axioms ReuseModel.SideTables.RecordedWrite

#check @UnsupportedAccess
#print axioms ReuseModel.SideTables.UnsupportedAccess
#check_axioms ReuseModel.SideTables.UnsupportedAccess

#check @valueDom_hit
#print axioms Checks.valueDom_hit
#check_axioms Checks.valueDom_hit

#check hitStmt
#print axioms Checks.hitStmt
#check_axioms Checks.hitStmt

#check hitSubject
#print axioms Checks.hitSubject
#check_axioms Checks.hitSubject

#check hitEntry
#print axioms Checks.hitEntry
#check_axioms Checks.hitEntry

#check hitCurrent
#print axioms Checks.hitCurrent
#check_axioms Checks.hitCurrent

#check hitProducer
#print axioms Checks.hitProducer
#check_axioms Checks.hitProducer

#check hitMember
#print axioms Checks.hitMember
#check_axioms Checks.hitMember

#check hitOutput
#print axioms Checks.hitOutput
#check_axioms Checks.hitOutput

#check value_hit_distinct_member
#print axioms Checks.value_hit_distinct_member
#check_axioms Checks.value_hit_distinct_member

#check hit_observations_do_not_imply_match
#print axioms Checks.hit_observations_do_not_imply_match
#check_axioms Checks.hit_observations_do_not_imply_match

#check hit_needs_write_liveness
#print axioms Checks.hit_needs_write_liveness
#check_axioms Checks.hit_needs_write_liveness

#check hit_needs_allocator_agreement
#print axioms Checks.hit_needs_allocator_agreement
#check_axioms Checks.hit_needs_allocator_agreement

#check allocator_mismatch_loses_exit
#print axioms Checks.allocator_mismatch_loses_exit
#check_axioms Checks.allocator_mismatch_loses_exit

#check hit_needs_no_frame_rewrite
#print axioms Checks.hit_needs_no_frame_rewrite
#check_axioms Checks.hit_needs_no_frame_rewrite

#check hit_frame_absent_bindings
#print axioms Checks.hit_frame_absent_bindings
#check_axioms Checks.hit_frame_absent_bindings

#check side_table_contracts
#print axioms Checks.side_table_contracts
#check_axioms Checks.side_table_contracts

#check fixed_read_needs_run_invariance
#print axioms Checks.fixed_read_needs_run_invariance
#check_axioms Checks.fixed_read_needs_run_invariance

#check keyed_read_can_miss_nested_read
#print axioms Checks.keyed_read_can_miss_nested_read
#check_axioms Checks.keyed_read_can_miss_nested_read

#check recorded_write_preserves_current_reach
#print axioms Checks.recorded_write_preserves_current_reach
#check_axioms Checks.recorded_write_preserves_current_reach

#check recorded_write_needs_fresh_coverage
#print axioms Checks.recorded_write_needs_fresh_coverage
#check_axioms Checks.recorded_write_needs_fresh_coverage

#check recorded_write_preserves_other_positions
#print axioms Checks.recorded_write_preserves_other_positions
#check_axioms Checks.recorded_write_preserves_other_positions

#check unsupported_producer_prevents_storage
#print axioms Checks.unsupported_producer_prevents_storage
#check_axioms Checks.unsupported_producer_prevents_storage

#check projectedPredicates
#print axioms Checks.projectedPredicates
#check_axioms Checks.projectedPredicates

#check allocatorEntry
#print axioms Checks.allocatorEntry
#check_axioms Checks.allocatorEntry

#check shortState
#print axioms Checks.shortState
#check_axioms Checks.shortState

#check allocCur
#print axioms Checks.allocCur
#check_axioms Checks.allocCur

#check projectedSweep
#print axioms Checks.projectedSweep
#check_axioms Checks.projectedSweep

#check sweepCur
#print axioms Checks.sweepCur
#check_axioms Checks.sweepCur

end
