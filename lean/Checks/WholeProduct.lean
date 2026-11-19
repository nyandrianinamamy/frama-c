import Checks.Domains

/-!
For `w = x`, blocks 0, 1 and 2 are `x`, `w` and `z`. A projected
hit can combine the written value from a stored exit for `x = 1` with
the frame of a current member with `x = z = 0`. Fresh execution from
the current input preserves the relation between the copied value and `z`.
-/

namespace Checks

open ReuseModel Memory Domain

-- Here filtering really projects equalities, unlike the identity filter
-- tested in Checks.Domains. Keep an equality only when both ends are keyed.
private def projectedEq : Domain FunMem :=
  { eqDom FunMem with
    filter := fun B S => S.filter fun p => decide (p.1 ∈ B ∧ p.2 ∈ B) }

private theorem projectedEq_filterSound : projectedEq.FilterSound := by
  intro B S m hm p hp
  exact hm p (List.mem_filter.mp hp).1

private theorem projectedEq_relateSound : projectedEq.RelateSound where
  existing := eqDom_existing
  decomposes B S hclosed := by
    obtain ⟨R, hR, hsub⟩ := hclosed
    change List (Block × Block) at S
    have inside (p : Block × Block) (hp : p ∈ S) (ht : p.1 ∈ B ∨ p.2 ∈ B) :
        p.1 ∈ B ∧ p.2 ∈ B := by
      have hR' : ((S.filter fun p => decide (p.1 ∈ B ∨ p.2 ∈ B)).flatMap
          fun p => [p.1, p.2]) = R := Option.some.inj hR
      have hp' : p ∈ S.filter (fun p => decide (p.1 ∈ B ∨ p.2 ∈ B)) :=
        List.mem_filter.mpr ⟨hp, decide_eq_true ht⟩
      exact ⟨hsub _ (hR' ▸ List.mem_flatMap.mpr ⟨p, hp', by simp⟩),
        hsub _ (hR' ▸ List.mem_flatMap.mpr ⟨p, hp', by simp⟩)⟩
    constructor
    · intro m m' hag hm p hp
      have hB := of_decide_eq_true (List.mem_filter.mp hp).2
      obtain ⟨v, h₁, h₂⟩ := hm p hp
      exact ⟨v, (hag _ hB.1).symm.trans h₁, (hag _ hB.2).symm.trans h₂⟩
    · intro m
      constructor
      · intro hm
        exact ⟨projectedEq_filterSound B S m hm, m, hm, fun _ _ => rfl⟩
      · rintro ⟨hf, w, hw, hoff⟩ p hp
        by_cases ht : p.1 ∈ B ∨ p.2 ∈ B
        · exact hf p (List.mem_filter.mpr ⟨hp, decide_eq_true (inside p hp ht)⟩)
        · obtain ⟨v, h₁, h₂⟩ := hw p hp
          exact ⟨v, (hoff _ fun h => ht (Or.inl h)).trans h₁,
            (hoff _ fun h => ht (Or.inr h)).trans h₂⟩

def copyProduct : Domain FunMem := (valueDom FunMem).prod projectedEq

private def copyProg : Program :=
  { globals := fun x => if x = "x" then some 0 else if x = "w" then some 1
      else if x = "z" then some 2 else none
    funs := [] }

private def copyStmt : Stmt := .assign 1 (.var "w") (.var "x")

private def copySubject : Subject := ⟨copyProg, copyStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

private def bits : List Value := [.int 0, .int 1]

private def copyValues : (valueDom FunMem).State := [(0, bits), (1, [.int 0])]

def copyEntry : CacheEntry copyProduct where
  subject := copySubject
  env := fun _ => none
  input := (copyValues, [])
  key := [0]
  footprint := ⟨[0], [1], [1], [1]⟩
  exit := fun o => if o = .completed then ([(1, bits)], [(0, 1)]) else ([(1, [])], [])
  violations := fun _ => False
  reached := (· = 1)

def copyCurrent : copyProduct.State := (copyValues, [(0, 2)])

def copyFresh : CacheEntry copyProduct :=
  { copyEntry with
    input := copyCurrent
    exit := fun o => if o = .completed then ([(1, bits)], [(1, 2)]) else ([(1, [])], []) }

def copyMem (x w z : Int) : FunMem := memOf [.int x, .int w, .int z]

private theorem copy_input {x z : Int} (hx : Value.int x ∈ bits) :
    copyProduct.γ copyEntry.input (copyMem x 0 z) := by
  constructor
  · intro p hp
    change p ∈ [(0, bits), (1, [Value.int 0])] at hp
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl
    · exact ⟨_, hx, rfl⟩
    · exact ⟨_, List.mem_singleton_self _, rfl⟩
  · intro p hp
    exact (List.not_mem_nil hp).elim

private theorem copy_current : copyProduct.γ copyCurrent (copyMem 0 0 0) := by
  refine ⟨(copy_input (z := 0) List.mem_cons_self).1, ?_⟩
  intro p hp
  rcases List.mem_singleton.mp hp with rfl
  exact ⟨.int 0, rfl, rfl⟩

private def copyEvents : List Event := [.read 0, .write 1]

private theorem copy_assign {m out : FunMem} {v : Value}
    (hx : load m 0 = some v) (hs : store m 1 v = some out) :
    execAssign copyProg copyEntry.env m (.var "w") (.var "x") =
      (copyEvents, .ok out) := by
  simp [execAssign, evalLExpr, evalExpr, resolve, copyEntry, copyProg,
    loadValue, hx, hs, copyEvents]

private def CopyTrace (m : FunMem) (v : Value) (evs : List Event)
    (c : Config FunMem) : Prop :=
  (evs = [] ∨ evs = copyEvents) ∧
  match c with
  | .run s .. => s = copyStmt
  | .next .. => True
  | .done o out => o = .completed ∧ evs = copyEvents ∧
      load out 1 = some v ∧ load out 0 = load m 0 ∧ load out 2 = load m 2
  | _ => False

private theorem copy_trace {m : FunMem} {evs : List Event} {c : Config FunMem}
    {v : Value} (hx : load m 0 = some v) (hw : load m 1 = some (.int 0))
    (h : Prefix copyEntry.subject ⟨copyEntry.env, m⟩ evs c) :
    CopyTrace m v evs c := by
  obtain ⟨n, hn⟩ := steps_run h
  change run copyProg n (Config.entry copyStmt ⟨copyEntry.env, m⟩) = _ at hn
  have hs : (store m 1 v).isSome = true := by rw [store_ok_iff, hw]; rfl
  cases hstore : store m 1 v with
  | none => rw [hstore] at hs; contradiction
  | some out =>
    have assign := copy_assign hx hstore
    have finished (n : Nat) :
        run copyProg n (.done .completed out) = ([], .done .completed out) := by
      cases n <;> rfl
    rcases n with _ | _ | n
    all_goals
      simp only [run, Config.entry, copyStmt, step, stepStmt, stepNext, assign,
        finished, List.append_nil] at hn
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj hn
      simp [CopyTrace, copyStmt, load_store_same hstore, load_store_other hstore
        (by decide : (0 : Block) ≠ 1), load_store_other hstore (by decide : (2 : Block) ≠ 1)]

private theorem copy_traced {m : FunMem} (hm : (valueDom FunMem).γ copyValues m) :
    ∃ v ∈ bits, load m 0 = some v ∧ ∀ evs c, Prefix copyEntry.subject ⟨copyEntry.env, m⟩ evs c →
      CopyTrace m v evs c := by
  obtain ⟨v, hv, hx⟩ := hm (0, bits) List.mem_cons_self
  obtain ⟨w, hw, hl⟩ := hm (1, [.int 0]) (List.mem_cons_of_mem _ (List.mem_singleton_self _))
  rw [List.mem_singleton.mp hw] at hl
  exact ⟨v, hv, hx, fun _ _ h => copy_trace hx hl h⟩

private theorem copy_coverage : copyEntry.Coverage := by
  intro m hm
  obtain ⟨v, _, _, ht⟩ := copy_traced hm.1
  constructor
  · intro evs c hp
    rcases (ht evs c hp).1 with rfl | rfl <;>
      simp [copyEntry, copyEvents, AccessesCovered]
  · intro evs o out hp b hb
    have he := (ht evs _ hp).2.2.1
    simpa [he, copyEntry, copyEvents] using hb
  · intro evs o out hp b hb
    have he := (ht evs _ hp).2.2.1
    simpa [he, copyEntry, copyEvents] using hb

private theorem copy_producer : copyEntry.ProducerSound := by
  constructor
  · rintro m hm o out ⟨evs, hp⟩
    obtain ⟨v, hv, hload, ht⟩ := copy_traced hm.1
    obtain ⟨rfl, _, hw, hx, _⟩ := (ht evs _ hp).2
    constructor
    · intro p hp
      have hp' : p ∈ [(1, bits)] := by simpa [copyEntry] using hp
      rcases List.mem_singleton.mp hp' with rfl
      exact ⟨v, hv, hw⟩
    · intro p hp
      have hp' : p ∈ ([(0, 1)] : List (Block × Block)) := by simpa [copyEntry] using hp
      rcases List.mem_singleton.mp hp' with rfl
      exact ⟨v, hx.trans hload, hw⟩
  · intro m hm v hv
    obtain ⟨_, _, _, ht⟩ := copy_traced hm.1
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, hp⟩ := hv
      exact (ht evs _ hp).2
    | assertion l =>
      obtain ⟨evs, e, k, env, atVisit, hp, _⟩ := hv
      have h := (ht evs _ hp).2
      simp [copyStmt] at h
  · rintro m hm l ⟨env, atVisit, evs, s, k, hp, rfl⟩
    obtain ⟨_, _, _, ht⟩ := copy_traced hm.1
    have h : s = copyStmt := (ht evs _ hp).2
    subst s
    rfl

private theorem copy_sound : copyEntry.Sound FunMem.allocatorAgreement :=
  copyEntry.sound_of_producer ⟨copyMem 0 0 0, copy_input List.mem_cons_self⟩
    copy_producer copy_coverage (by simp [CacheEntry.KeyCovers, copyEntry])

private theorem copy_current_stored {m : FunMem} (hm : copyProduct.γ copyCurrent m) :
    copyProduct.γ copyEntry.input m :=
  ⟨hm.1, fun _ hp => (List.not_mem_nil hp).elim⟩

private theorem copy_frame {m : FunMem} (hm : (valueDom FunMem).γ copyValues m) :
    copyEntry.NoFrameRewrite m := by
  intro evs o out hp b hb target ht
  obtain ⟨_, _, _, h⟩ := copy_traced hm
  have he := (h evs _ hp).2.2.1
  simp [he, copyEvents, sweepTargets] at ht

private theorem copy_reuse : copyProduct.ReuseSound :=
  reuseSound_prod valueDom_reuseSound eqDom_reuseSound

private theorem copy_fresh_producer : copyFresh.ProducerSound := by
  constructor
  · rintro m hm o out ⟨evs, hp⟩
    have hs := copy_producer.exit m (copy_current_stored hm) o out ⟨evs, hp⟩
    obtain ⟨_, _, _, ht⟩ := copy_traced hm.1
    obtain ⟨rfl, _, _, hx, hz⟩ := (ht evs _ hp).2
    refine ⟨hs.1, ?_⟩
    intro p hp'
    have hp'' : p ∈ ([(1, 2)] : List (Block × Block)) := by simpa [copyFresh] using hp'
    rcases List.mem_singleton.mp hp'' with rfl
    obtain ⟨v, h₀, h₂⟩ := hm.2 (0, 2) (List.mem_singleton_self _)
    obtain ⟨v', h₀', h₁⟩ := hs.2 (0, 1) (by decide)
    rw [hx, h₀] at h₀'
    cases h₀'
    exact ⟨v, h₁, hz.trans h₂⟩
  · exact fun m hm => copy_producer.safety m (copy_current_stored hm)
  · exact fun m hm => copy_producer.reach m (copy_current_stored hm)

private theorem copy_run (x z : Int) :
    Exit copyEntry.subject ⟨copyEntry.env, copyMem x 0 z⟩ .completed (copyMem x x z) := by
  have hs : store (copyMem x 0 z) 1 (.int x) = some (copyMem x x z) := by
    change FunMem.store _ _ _ = _
    unfold FunMem.store
    split
    · congr 1
      apply (FunMem.mk.injEq ..).mpr
      refine ⟨?_, rfl⟩
      funext b
      by_cases hb : b = 1
      · subst b; rfl
      · simp [copyMem, memOf, createAll, FunMem.instMemory, FunMem.create,
          FunMem.empty, updateCell, hb]
    · rename_i h
      exact (h rfl).elim
  have hrun := run_steps copyProg 2 (Config.entry copyStmt ⟨copyEntry.env, copyMem x 0 z⟩)
  refine ⟨copyEvents, ?_⟩
  simpa only [run, Config.entry, copyStmt, step, stepStmt, stepNext,
    copy_assign rfl hs, List.append_nil] using hrun

/-- Equal products use the same concrete witness. A different equality
component or a different value constraint outside the key rejects lookup. -/
theorem whole_product_copy_hit :
    let other : copyProduct.State := ([(0, [.int 0, .int 1]), (1, [.int 1])], [])
    copyEntry.WholeProductMatch copyEntry.input ∧
    copyEntry.HitObservations copyEntry.input (copyMem 0 0 0) ∧
    ¬ copyEntry.WholeProductMatch copyCurrent ∧
    copyProduct.filter copyEntry.key other = copyProduct.filter copyEntry.key copyEntry.input ∧
    ¬ copyEntry.WholeProductMatch other := by
  refine ⟨rfl, copyEntry.hit_of_whole_product copy_sound rfl (fun o => copy_reuse _ _ _)
    (fun _ hm => copy_frame hm.1) _ (copy_input List.mem_cons_self), ?_, rfl, ?_⟩
  · intro heq
    have h := congrArg Prod.snd heq
    cases h
  · intro heq
    have h := congrArg Prod.fst heq
    cases h

/-- Stored-side closure and equal projections allow a sound hit despite
the missing current-side closure. Its reuse includes a combination of
actual runs that the sound fresh relational exit excludes. -/
theorem projected_copy_loses_relation :
    copyEntry.Sound FunMem.allocatorAgreement ∧
    copyProduct.Closed copyEntry.key copyEntry.input ∧
    ¬ copyProduct.Closed copyEntry.key copyCurrent ∧
    copyProduct.filter copyEntry.key copyCurrent = copyProduct.filter copyEntry.key copyEntry.input ∧
    (∀ m, copyProduct.γ copyCurrent m → copyEntry.HitObservations copyCurrent m) ∧
    Exit copyEntry.subject ⟨copyEntry.env, copyMem 1 0 0⟩ .completed (copyMem 1 1 0) ∧
    Exit copyEntry.subject ⟨copyEntry.env, copyMem 0 0 0⟩ .completed (copyMem 0 0 0) ∧
    copyProduct.γ (copyProduct.reuse copyEntry.footprint.exitWrites copyCurrent
      (copyEntry.exit .completed)) (copyMem 0 1 0) ∧
    copyFresh.ProducerSound ∧
    (∀ m, copyProduct.γ (copyFresh.exit .completed) m → load m 1 = load m 2) ∧
    ¬ copyProduct.γ (copyFresh.exit .completed) (copyMem 0 1 0) := by
  have hclosed : copyProduct.Closed copyEntry.key copyEntry.input :=
    ⟨[], rfl, by simp⟩
  have hproj : copyProduct.filter copyEntry.key copyCurrent =
      copyProduct.filter copyEntry.key copyEntry.input := rfl
  have hit : ∀ m, copyProduct.γ copyCurrent m → copyEntry.HitObservations copyCurrent m :=
    copyEntry.hit copy_sound (filterSound_prod valueDom_filterSound projectedEq_filterSound _ _)
      (product_lemma FunMem.combinable valueDom_relateSound projectedEq_relateSound
        hclosed copy_sound.nonempty)
      (fun _ h => hproj ▸ h)
      (fun _ hm _ => CacheEntry.matches_of_input (copy_current_stored hm))
      (fun o => copy_reuse _ _ _) (fun _ hm => copy_frame hm.1)
  have hrun₁ : Exit copyEntry.subject ⟨copyEntry.env, copyMem 1 0 0⟩
      .completed (copyMem 1 1 0) := copy_run 1 0
  have hrun₀ : Exit copyEntry.subject ⟨copyEntry.env, copyMem 0 0 0⟩
      .completed (copyMem 0 0 0) := copy_run 0 0
  have hfresh : ∀ m, copyProduct.γ (copyFresh.exit .completed) m →
      load m 1 = load m 2 := by
    intro m hm
    obtain ⟨v, h₁, h₂⟩ := hm.2 (1, 2) (by decide)
    exact h₁.trans h₂.symm
  refine ⟨copy_sound, hclosed, ?_, hproj, hit, hrun₁, hrun₀, ?_, copy_fresh_producer,
    hfresh, fun hm => ?_⟩
  · rintro ⟨R, hR, hsub⟩
    have he : [0, 2] = R := Option.some.inj hR
    have hz := hsub 2 (he ▸ by decide)
    contradiction
  · refine copy_reuse _ _ _ _ _ _ copy_current
      (copy_producer.exit _ (copy_input (by decide)) _ _ hrun₁) ?_ ?_
    · intro b hb
      rcases List.mem_singleton.mp hb with rfl
      rfl
    · intro b hb
      change b ∉ [1] at hb
      have hne : b ≠ 1 := fun h => hb (List.mem_singleton.mpr h)
      simp [copyMem, memOf, createAll, FunMem.instMemory, FunMem.empty, FunMem.create, updateCell, hne]
  · have h := hfresh _ hm
    change some (Value.int 1) = some (.int 0) at h
    contradiction

end Checks
