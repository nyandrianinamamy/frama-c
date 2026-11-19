import ReuseModel.Entry
import ReuseModel.Frame

/-!
# A hit within one analysis

Projection supplies key agreement. Admission must extend it to a joint
replay witness. Exit then combines the stored witness on possible exit
writes with the current frame, provided the recorded sweeps leave it intact.
-/

namespace ReuseModel.CacheEntry

open Memory

variable {M : Type} [Memory M] {d : Domain M}

/-- Key agreement can be extended to write-target liveness and allocator
agreement. The resulting witness must satisfy all three at once. -/
def ReplayCompatible (entry : CacheEntry d) (a : AllocatorAgreement M)
    (cur : d.State) : Prop :=
  ∀ m, d.γ cur m → (∃ w, d.γ entry.input w ∧ AgreeOn entry.key m w) →
    entry.Matches a m

/-- A projected match with admission gives the witness used by entry replay. -/
theorem matches_of_projected {entry : CacheEntry d} {a : AllocatorAgreement M}
    {cur : d.State} (hf : ∀ m, d.γ cur m → d.γ (d.filter entry.key cur) m) (hex : d.ExactOn entry.key entry.input)
    (hsub : ∀ m, d.γ (d.filter entry.key cur) m → d.γ (d.filter entry.key entry.input) m)
    (hcompat : entry.ReplayCompatible a cur) {m : M} (hm : d.γ cur m) :
    entry.Matches a m :=
  hcompat m hm (Domain.match_lemma hf hsub hex hm).2

/-- Under the projection hypotheses, compatibility is exactly the
existence of a joint replay witness for every current member. -/
theorem replayCompatible_iff_matches {entry : CacheEntry d} {a : AllocatorAgreement M}
    {cur : d.State} (hf : ∀ m, d.γ cur m → d.γ (d.filter entry.key cur) m)
    (hex : d.ExactOn entry.key entry.input)
    (hsub : ∀ m, d.γ (d.filter entry.key cur) m → d.γ (d.filter entry.key entry.input) m) :
    entry.ReplayCompatible a cur ↔ ∀ m, d.γ cur m → entry.Matches a m :=
  ⟨fun hcompat _ hm => matches_of_projected hf hex hsub hcompat hm,
    fun h m hm _ => h m hm⟩

/-- Every frame holder in the current memory avoids the targets of the
sweeps performed on a normal exit. The condition uses that exit's trace. -/
def NoFrameRewrite (entry : CacheEntry d) (m : M) : Prop :=
  ∀ evs o out, Prefix entry.subject ⟨entry.env, m⟩ evs (.done o out) →
    ∀ b ∉ entry.footprint.exitWrites, ∀ target ∈ sweepTargets evs,
      load m b ≠ some (.ptr target)

/-- On a covered normal exit, avoiding the sweep targets is exactly the
condition for leaving all bindings outside the overlay unchanged. -/
theorem exit_frame_iff {entry : CacheEntry d} {m out : M}
    (hc : entry.Covers m) {evs : List Event} {o : Outcome}
    (hp : Prefix entry.subject ⟨entry.env, m⟩ evs (.done o out)) :
    AgreeOff entry.footprint.exitWrites out m ↔
      ∀ b ∉ entry.footprint.exitWrites, ∀ target ∈ sweepTargets evs,
        load m b ≠ some (.ptr target) := by
  have frame (b : Block) (hb : b ∉ entry.footprint.exitWrites) :
      load out b = applySweeps (sweepTargets evs) (load m b) := by
    cases hload : load m b with
    | none =>
      rw [exit_preserves_absence hload hp, (applySweeps_eq_iff _ _).2 (by simp)]
    | some v =>
      have hi : Issued m b := issued_of_load hload
      rw [← hload]
      refine frame_of_not_written hi hp ?_
      intro e he hw
      cases e <;> simp only [Event.Writes] at hw
      case write dst => exact hb (hc.exitWrites evs o out hp b (hw ▸ he))
  constructor
  · intro h b hb
    exact (applySweeps_eq_iff _ _).1 ((frame b hb).symm.trans (h b hb))
  · intro h b hb
    exact (frame b hb).trans ((applySweeps_eq_iff _ _).2 (h b hb))

/-- Exit uses the actual current frame. Reach and Safety apply to every finite
prefix, and a valid status means the assertion holds at each visit. -/
structure HitObservations (entry : CacheEntry d) (cur : d.State) (m : M) : Prop where
  exit : ∀ o out, Exit entry.subject ⟨entry.env, m⟩ o out →
    d.γ (d.reuse entry.footprint.exitWrites cur (entry.exit o)) out ∧
    AgreeOff entry.footprint.exitWrites out m
  reach : ∀ l, Reach entry.subject ⟨entry.env, m⟩ l → entry.reached l
  safety : ∀ v, Unsafe entry.subject ⟨entry.env, m⟩ v → entry.violations v
  valid : ∀ l e k env atVisit evs,
    ¬ entry.violations (.assertion l) →
    Prefix entry.subject ⟨entry.env, m⟩ evs (.run (.assert l e) k env atVisit) →
    assertionHolds entry.subject.prog env atVisit e = true

/-- The common hit argument, for any matching rule supplying a witness. -/
theorem hit_of_matches {entry : CacheEntry d} {a : AllocatorAgreement M}
    {cur : d.State} (hs : entry.Sound a) (hr : ∀ o, d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o))
    {m : M} (hm : d.γ cur m) (hmatch : entry.Matches a m)
    (hframe : entry.NoFrameRewrite m) : entry.HitObservations cur m := by
  obtain ⟨hc, ho⟩ := hs.matched m hmatch
  refine ⟨?_, ho.reach, ho.safety, ?_⟩
  · intro o out he
    obtain ⟨w, hw, hon⟩ := ho.exit o out he
    obtain ⟨evs, hp⟩ := he
    have hoff := (exit_frame_iff hc hp).2 (hframe evs o out hp)
    exact ⟨hr o m w out hm hw hon.symm hoff, hoff⟩
  · intro l e k env atVisit evs hv hp
    cases he : assertionHolds entry.subject.prog env atVisit e
    · exact False.elim (hv (ho.safety (.assertion l) ⟨evs, e, k, env, atVisit, hp, he⟩))
    · rfl

/-- Compose a joint replay witness supplied by compatibility with entry soundness,
frame preservation and sound reuse. The same subject and entry bindings are
used throughout. -/
theorem hit {entry : CacheEntry d} {a : AllocatorAgreement M}
    {cur : d.State} (hs : entry.Sound a) (hf : ∀ m, d.γ cur m → d.γ (d.filter entry.key cur) m)
    (hex : d.ExactOn entry.key entry.input)
    (hsub : ∀ m, d.γ (d.filter entry.key cur) m → d.γ (d.filter entry.key entry.input) m)
    (hcompat : entry.ReplayCompatible a cur) (hr : ∀ o, d.ReuseSoundAt entry.footprint.exitWrites cur (entry.exit o))
    (hframe : ∀ m, d.γ cur m → entry.NoFrameRewrite m) :
    ∀ m, d.γ cur m → entry.HitObservations cur m :=
  fun m hm => hit_of_matches hs hr hm (matches_of_projected hf hex hsub hcompat hm)
    (hframe m hm)

end ReuseModel.CacheEntry
