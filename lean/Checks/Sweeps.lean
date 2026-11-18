import ReuseModel
import Checks.Examples

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

private theorem sweep_fixture_frame (σ : State FunMem)
    (hs : ∀ n : Nat, sweepRun σ (n + 7) = sweepRun σ 7)
    (hf : ∀ n : Fin 8, ∀ e ∈ (sweepRun σ n).1, e ≠ .read 1 ∧ e ≠ .write 1) :
    InFrame sweepSubj σ 1 := by
  intro evs c hp e he ha
  obtain ⟨fuel, hrun⟩ := steps_run hp
  change sweepRun σ fuel = (evs, c) at hrun
  have h : ∃ n : Fin 8, sweepRun σ n = (evs, c) := by
    by_cases hlt : fuel < 8
    · exact ⟨⟨fuel, hlt⟩, hrun⟩
    · have h : fuel = (fuel - 7) + 7 := by omega
      rw [h, hs] at hrun
      exact ⟨7, hrun⟩
  obtain ⟨n, hn⟩ := h
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

end Checks
