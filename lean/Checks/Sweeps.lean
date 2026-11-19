import ReuseModel
import Checks.Entries

namespace Checks

open ReuseModel Memory

def sweepProg : Program := ⟨[], fun x => if x = "holder" then some 0 else none⟩

def sweepStmt : Stmt :=
  .seq 1 (.scope 2 [("local", 9)] (.assign 3 (.var "holder") (.addr "local")))
    (.skip 4)

def sweepSubj : Subject := ⟨sweepProg, sweepStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def sweepInput : State FunMem := topState [.int 0, .ptr 0]

theorem own_local_sweep :
    (run sweepProg 4 (Config.entry sweepStmt sweepInput)).1 =
      [.scopeEnter 2, .write 0, .sweep 2] ∧
    load (run sweepProg 4 (Config.entry sweepStmt sweepInput)).2.mem 0 =
      some (.escaped 2) ∧
    load (run sweepProg 4 (Config.entry sweepStmt sweepInput)).2.mem 2 = none := by
  decide

def sweepRun (σ : State FunMem) (n : Nat) : List Event × Config FunMem :=
  run sweepProg n (Config.entry sweepStmt σ)

def futurePointerInput : State FunMem := topState [.int 0, .ptr 2]

private theorem sweep_fixture_prefix {σ : State FunMem}
    (hs : ∀ n : Nat, sweepRun σ (n + 7) = sweepRun σ 7)
    {evs : List Event} {c : Config FunMem} (hp : Prefix sweepSubj σ evs c) :
    ∃ n : Fin 8, sweepRun σ n = (evs, c) := by
  obtain ⟨fuel, hrun⟩ := steps_run hp
  change sweepRun σ fuel = (evs, c) at hrun
  by_cases hlt : fuel < 8
  · exact ⟨⟨fuel, hlt⟩, hrun⟩
  · have h : fuel = (fuel - 7) + 7 := by omega
    rw [h, hs] at hrun
    exact ⟨7, hrun⟩

private theorem sweep_fixture_frame (σ : State FunMem)
    (hs : ∀ n : Nat, sweepRun σ (n + 7) = sweepRun σ 7)
    (hf : ∀ n : Fin 8, ∀ e ∈ (sweepRun σ n).1, e ≠ .read 1 ∧ e ≠ .write 1) :
    InFrame sweepSubj σ 1 := by
  intro evs c hp e he ha
  obtain ⟨n, hn⟩ := sweep_fixture_prefix hs hp
  have hne := hf n e (hn.symm ▸ he)
  cases e <;> simp_all [Event.Accesses]

/-- The sweep ran. The written holder is escaped, and the untouched live
block keeps its entry value at the next visit and at normal exit. -/
theorem own_local_frame_unchanged :
    InFrame sweepSubj sweepInput 1 ∧
    load (sweepRun sweepInput 5).2.mem 1 = some (.ptr 0) ∧
    load (sweepRun sweepInput 7).2.mem 1 = some (.ptr 0) := by
  have hframe : InFrame sweepSubj sweepInput 1 :=
    sweep_fixture_frame sweepInput (by intro n; cases n <;> rfl) (by decide)
  have hframeAt (n : Nat) : load (sweepRun sweepInput n).2.mem 1 = some (.ptr 0) := by
    have hp : Prefix sweepSubj sweepInput (sweepRun sweepInput n).1
        (sweepRun sweepInput n).2 := run_steps _ _ _
    have hlive : Live sweepInput.mem 1 := rfl
    have hload : load sweepInput.mem 1 = some (.ptr 0) := rfl
    have htarget : ∀ target, load sweepInput.mem 1 = some (.ptr target) →
        Issued sweepInput.mem target := by
      intro target h
      rw [hload] at h
      cases h
      exact Live.issued (show Live sweepInput.mem 0 from rfl)
    exact (frame_no_sweep_rewrite hlive.issued htarget hp
      fun e he hw => hframe _ _ hp e he (Event.accesses_of_writes hw)).trans hload
  exact ⟨hframe, hframeAt 5, hframeAt 7⟩

/-- Dropping the entry pointer condition is unsound. A separate untouched
holder points to the next identifier before it is issued. The sweep changes
that holder despite the absence of a designated access. -/
theorem future_pointer_needs_rewrite :
    InFrame sweepSubj futurePointerInput 1 ∧
    Live futurePointerInput.mem 1 ∧
    ¬ Issued futurePointerInput.mem 2 ∧
    sweepTargets (sweepRun futurePointerInput 5).1 = [2] ∧
    load futurePointerInput.mem 1 = some (.ptr 2) ∧
    load (sweepRun futurePointerInput 5).2.mem 1 = some (.escaped 2) := by
  have hframe : InFrame sweepSubj futurePointerInput 1 :=
    sweep_fixture_frame futurePointerInput (by intro n; cases n <;> rfl) (by decide)
  have hp : Prefix sweepSubj futurePointerInput (sweepRun futurePointerInput 5).1
      (sweepRun futurePointerInput 5).2 := run_steps _ _ _
  have ht : 2 ∈ sweepTargets (sweepRun futurePointerInput 5).1 := by decide
  exact ⟨hframe, rfl, sweep_target_fresh hp ht, rfl, rfl, frame_lemma (show Live futurePointerInput.mem 1 from rfl) hframe hp⟩

/-- Returning from an inner block also sweeps, including a pointer to the
local carried by the in-flight return. -/
theorem return_sweeps_local :
    (run sweepProg 4 (Config.entry
      (.scope 10 [("local", 9)] (.ret 11 (some (.addr "local")))) sweepInput)).1 =
      [.scopeEnter 2, .sweep 2] ∧
    outcomeOf? (run sweepProg 4 (Config.entry
      (.scope 10 [("local", 9)] (.ret 11 (some (.addr "local")))) sweepInput)).2 =
      some (.returned (some (.escaped 2))) := by
  decide

def sweepEntry : CacheEntry predicates where
  subject := sweepSubj
  env := noLocals
  input := (· = sweepInput.mem)
  key := [0]
  footprint := ⟨[], [0], [0], []⟩
  exit := fun _ _ => True
  violations := fun _ => True
  reached := fun _ => True

private theorem sweep_entry_coverage : sweepEntry.Coverage := by
  rintro m (rfl : m = sweepInput.mem)
  have traces : ∀ n : Fin 8, ∀ e ∈ (sweepRun sweepInput n).1,
      e = .scopeEnter 2 ∨ e = .write 0 ∨ e = .sweep 2 := by decide
  have events {evs : List Event} {c : Config FunMem}
      (hp : Prefix sweepSubj sweepInput evs c) :
      ∀ e ∈ evs, e = .scopeEnter 2 ∨ e = .write 0 ∨ e = .sweep 2 := by
    obtain ⟨n, hn⟩ := sweep_fixture_prefix (by intro k; cases k <;> rfl) hp
    simpa only [hn] using traces n
  constructor
  · intro evs c hp e he
    rcases events hp e he with rfl | rfl | rfl <;> decide
  · intro evs o out hp b hb
    rcases events hp (.write b) hb with h | h | h
    · contradiction
    · cases h; exact List.mem_cons_self
    · contradiction
  · intro evs o out hp b hb
    contradiction

/-- A sound entry can match a distinct input whose untouched frame holder
changes on a normal exit even though it is outside the exit overlay. -/
theorem matching_frame_holder_rewritten :
    sweepEntry.Sound FunMem.allocatorAgreement ∧
      sweepEntry.Matches FunMem.allocatorAgreement futurePointerInput.mem ∧
      futurePointerInput.mem ≠ sweepInput.mem ∧
      sweepEntry.footprint.exitWrites = [0] ∧
      InFrame sweepSubj futurePointerInput 1 ∧ Issued futurePointerInput.mem 1 ∧
      Exit sweepSubj futurePointerInput .completed (sweepRun futurePointerInput 7).2.mem ∧
      (sweepRun futurePointerInput 7).1 = [.scopeEnter 2, .write 0, .sweep 2] ∧
      load futurePointerInput.mem 1 = some (.ptr 2) ∧
      load (sweepRun futurePointerInput 7).2.mem 1 = some (.escaped 2) := by
  have hs := sweepEntry.sound_of_producer (a := FunMem.allocatorAgreement)
    ⟨sweepInput.mem, rfl⟩ ⟨by intros; trivial, by intros; trivial, by intros; trivial⟩
    sweep_entry_coverage ⟨by intro b hb; contradiction, by intro b hb _; exact hb⟩
  have hm : sweepEntry.Matches FunMem.allocatorAgreement futurePointerInput.mem := by
    refine ⟨sweepInput.mem, rfl, ⟨?_, ?_, rfl⟩⟩ <;>
      intro b hb <;> change b ∈ [0] at hb <;>
      simp only [List.mem_singleton] at hb <;> subst b <;> rfl
  have hne : futurePointerInput.mem ≠ sweepInput.mem := by
    intro h
    have hload := congrArg (fun m => load m 1) h
    contradiction
  exact ⟨hs, hm, hne, rfl, future_pointer_needs_rewrite.1,
    Live.issued future_pointer_needs_rewrite.2.1, ⟨_, run_steps _ 7 _⟩, rfl, rfl, rfl⟩

def sweptHolderComparison : Stmt :=
  .seq 1 (.scope 2 [("t", 9)] (.assign 3 (.var "holder") (.addr "t")))
    (.ret 4 (some (.binop .eq (.var "holder") (.const 0))))

/-- Reading the marked value itself succeeds in the model. -/
theorem swept_holder_comparison_returns :
    (run sweepProg 9 (Config.entry sweptHolderComparison sweepInput)).1 =
      [.scopeEnter 2, .write 0, .sweep 2, .read 0] ∧
    outcomeOf? (run sweepProg 9 (Config.entry sweptHolderComparison sweepInput)).2 =
      some (.returned (some (.int 0))) := by decide

def nestedSweepBody : Stmt :=
  .scope 10 [("t", 9)] (.assign 11 (.var "holder") (.addr "t"))

def nestedSweepCall : Stmt := .call 1 none "callee" []

def nestedSweepProgram : Program :=
  ⟨[("callee", ⟨[], [], nestedSweepBody⟩)], sweepProg.globals⟩

/-- The caller's trace includes the callee's sweep as well. A lexical
sweep event alone does not establish ownership by the cached unit. -/
theorem nested_scope_sweep_in_caller :
    nestedSweepBody ∉ nestedSweepCall.subs ∧
    (run nestedSweepProgram 10 (Config.entry nestedSweepBody sweepInput)).1 =
      [.scopeEnter 2, .write 0, .sweep 2] ∧
    (run nestedSweepProgram 10 (Config.entry nestedSweepCall sweepInput)).1 =
      (run nestedSweepProgram 10 (Config.entry nestedSweepBody sweepInput)).1 ∧
    load (run nestedSweepProgram 10 (Config.entry nestedSweepCall sweepInput)).2.mem 0 =
      some (.escaped 2) := by decide

end Checks
