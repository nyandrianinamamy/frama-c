import ReuseModel
import Checks.Entries

namespace Checks

open ReuseModel Memory

def innerProg : Program := ⟨[], fun x =>
  if x = "i" then some 0 else if x = "other" then some 1 else none⟩

/-- i = 0; while (i < 2) { L: i++; } with L = 4. -/
def innerStmt : Stmt :=
  .seq 1 (.assign 2 (.var "i") (.const 0))
    (.loop 3 (.binop .lt (.var "i") (.const 2))
      (.assign 4 (.var "i") (.binop .add (.var "i") (.const 1))))

def innerSubj : Subject := ⟨innerProg, innerStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def innerProducer : FunMem := memOf [.int 9, .int 7]
def innerMember : FunMem := memOf [.int 9, .int 8]

def innerEntry : CacheEntry predicates where
  subject := innerSubj
  env := noLocals
  input := (· = innerProducer)
  key := [0]
  footprint := ⟨[0], [0], [0], [0]⟩
  exit := fun o m => o = .completed ∧ load m 0 = some (.int 2)
  violations := fun _ => False
  reached := (· ∈ [1, 2, 3, 4])

/-- The saved state describes the two values at L and retains the producing
call's value of the other block. -/
def innerStates (l : Label) (m : FunMem) : Prop :=
  if l = 4 then
    (load m 0 = some (.int 0) ∨ load m 0 = some (.int 1)) ∧ load m 1 = some (.int 7)
  else True

private def loopRun (m : FunMem) (n : Nat) : List Event × Config FunMem :=
  run innerProg n (Config.entry innerStmt ⟨noLocals, m⟩)

private theorem producer_prefix {evs : List Event} {c : Config FunMem}
    (h : Prefix innerSubj ⟨noLocals, innerProducer⟩ evs c) :
    ∃ n : Fin 12, loopRun innerProducer n = (evs, c) := by
  obtain ⟨fuel, hf⟩ := steps_run h
  change loopRun innerProducer fuel = (evs, c) at hf
  by_cases hlt : fuel < 12
  · exact ⟨⟨fuel, hlt⟩, hf⟩
  · have hs (extra : Nat) : loopRun innerProducer (extra + 11) = loopRun innerProducer 11 := by
      cases extra <;> rfl
    have he : fuel = (fuel - 11) + 11 := by omega
    rw [he, hs] at hf
    exact ⟨11, hf⟩

private def ProducerTrace (evs : List Event) (c : Config FunMem) : Prop :=
  (∀ e ∈ evs, e = .read 0 ∨ e = .write 0) ∧
  (match c with
    | .run (.assert ..) _ _ _ => False
    | .run s _ _ m => s.label ∈ [1, 2, 3, 4] ∧ innerStates s.label m
    | .done o m => o = .completed ∧ load m 0 = some (.int 2) ∧ Event.write 0 ∈ evs
    | .fault .. => False
    | _ => True)

private instance (evs : List Event) (c : Config FunMem) :
    Decidable (ProducerTrace evs c) := by
  unfold ProducerTrace
  refine @instDecidableAnd _ _ inferInstance ?_
  split <;> first | infer_instance | unfold innerStates; infer_instance

private theorem producer_trace : ∀ n : Fin 12,
    ProducerTrace (loopRun innerProducer n).1 (loopRun innerProducer n).2 := by decide

/-- The loop fixture meets production, footprint, key and Inner premises for
every prefix and its normal exit. -/
theorem loop_entry_premises :
    innerEntry.ProducerSound ∧ innerEntry.Coverage ∧ innerEntry.KeyCovers ∧
      innerEntry.InnerSound innerStates := by
  have effects {evs : List Event} {c : Config FunMem}
      (h : Prefix innerSubj ⟨noLocals, innerProducer⟩ evs c) : ProducerTrace evs c := by
    obtain ⟨n, hn⟩ := producer_prefix h
    simpa only [hn] using producer_trace n
  refine ⟨⟨?_, ?_, ?_⟩, ?_, ?_, ?_⟩
  · rintro m (rfl : m = innerProducer) o out ⟨evs, he⟩
    obtain ⟨ho, hval, _⟩ := (effects he).2
    exact ⟨ho, hval⟩
  · rintro m (rfl : m = innerProducer) v hv
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, he⟩ := hv
      exact (effects he).2
    | assertion l =>
      obtain ⟨evs, e, k, env, out, he, _⟩ := hv
      exact (effects he).2
  · rintro m (rfl : m = innerProducer) l ⟨env, out, evs, s, k, he, rfl⟩
    have ht := (effects he).2
    cases s <;> first | exact ht.1 | contradiction
  · rintro m (rfl : m = innerProducer)
    constructor
    · intro evs c he e hm
      rcases (effects he).1 e hm with rfl | rfl <;> exact List.mem_cons_self
    · intro evs o out he b hb
      rcases (effects he).1 (.write b) hb with hb | hb
      · contradiction
      · cases hb; exact List.mem_cons_self
    · intro evs o out he b hb
      simp only [innerEntry, List.mem_singleton] at hb
      subst b
      exact (effects he).2.2.2
  · exact ⟨fun _ h => h, fun _ h _ => h⟩
  · rintro m (rfl : m = innerProducer) l env out ⟨evs, s, k, he, rfl⟩
    have ht := (effects he).2
    cases s <;> first | exact ⟨out, ht.2, fun _ _ => rfl⟩ | contradiction

theorem loop_member_matches : innerEntry.Matches FunMem.allocatorAgreement innerMember := by
  refine ⟨innerProducer, rfl, ⟨?_, ?_, rfl⟩⟩
  · intro b hb
    simp only [innerEntry, List.mem_singleton] at hb
    cases hb; rfl
  · intro b hb
    simp only [innerEntry, List.mem_singleton] at hb
    cases hb; rfl

theorem loop_shared_inner :
    ∀ i ∈ [0, 1], ∃ m w env, Visit innerSubj ⟨noLocals, innerMember⟩ 4 env m ∧
      load m 0 = some (.int i) ∧ predicates.γ (innerStates 4) w ∧
      AgreeOn innerEntry.key w m := by
  have atFuel (n : Nat) (i : Int)
      (hl : labelOf? (loopRun innerMember n).2 = some 4)
      (hv : load (loopRun innerMember n).2.mem 0 = some (.int i)) :
      ∃ m w env, Visit innerSubj ⟨noLocals, innerMember⟩ 4 env m ∧
        load m 0 = some (.int i) ∧ predicates.γ (innerStates 4) w ∧
        AgreeOn innerEntry.key w m := by
    obtain ⟨env, hvisit⟩ := visit_of_run (t := innerSubj) (n := n) hl
    obtain ⟨w, hγ, hagree⟩ := CacheEntry.shared_inner loop_entry_premises.2.2.2
      loop_entry_premises.2.1 loop_entry_premises.2.2.1 loop_member_matches hvisit
    exact ⟨_, w, env, hvisit, hv, hγ, hagree⟩
  intro i hi
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hi
  rcases hi with rfl | rfl
  · exact atFuel 4 0 (by decide) (by decide)
  · exact atFuel 7 1 (by decide) (by decide)

/-- The same saved state does not account for the matching member's other block. -/
theorem loop_inner_outside_key :
    ∃ m env, Visit innerSubj ⟨noLocals, innerMember⟩ 4 env m ∧
      ∀ w, predicates.γ (innerStates 4) w → ¬ AgreeOn [1] w m := by
  obtain ⟨env, hv⟩ := visit_of_run (t := innerSubj)
    (σ := ⟨noLocals, innerMember⟩) (n := 4) (l := 4) (by decide)
  refine ⟨_, env, hv, ?_⟩
  intro w hγ hkey
  have h := hkey 1 List.mem_cons_self
  change (_ ∨ _) ∧ load w 1 = some (.int 7) at hγ
  change load w 1 = some (.int 8) at h
  rw [hγ.2] at h
  contradiction

/-- A state that records just the first value at L fails the producing
all-visits premise on the second visit. -/
theorem loop_first_visit_insufficient :
    ¬ innerEntry.InnerSound (fun _ m => load m 0 = some (.int 0)) := by
  intro hs
  obtain ⟨env, hv⟩ := visit_of_run (t := innerSubj)
    (σ := ⟨noLocals, innerProducer⟩) (n := 7) (l := 4) (by decide)
  obtain ⟨w, hγ, hagree⟩ := hs innerProducer rfl 4 env _ hv
  have h := hagree 0 List.mem_cons_self
  change load w 0 = some (.int 1) at h
  change load w 0 = some (.int 0) at hγ
  rw [hγ] at h
  contradiction

end Checks
