import ReuseModel.Observations

/-!
# Frame lemma without sweeps

A block that a statement neither reads nor writes has, at every visit inside
the statement, the value it had at entry. The model has no sweep: the end of
the lifetime of a callee's locals rewrites no other block.

`frame_of_not_written` is the general form: it holds at every configuration of
a finite prefix, for a block issued before entry, and needs only that the
prefix does not write the block. `frame_lemma` is the form used by the
correspondence record.
-/

namespace ReuseModel

open Memory

/-- The blocks held as locals by the call frames of a continuation. -/
def Cont.frameBlocks : Cont → List Block
  | .stop => []
  | .seq _ k => k.frameBlocks
  | .loop _ _ _ k => k.frameBlocks
  | .call _ _ _ locals k => locals ++ k.frameBlocks

section
variable {M : Type} [Memory M]

/-- `b` is in the frame of `s` from `σ`: no finite prefix of the execution of
`s` from `σ` reads or writes `b`. -/
def InFrame (p : Program) (s : Stmt) (σ : State M) (b : Block) : Prop :=
  ∀ evs c, Prefix p s σ evs c → ∀ e ∈ evs, ¬ e.Accesses b

/-- Invariant of the proof: `b` has been issued, and no call frame of the
configuration holds `b` as a local. -/
def FrameInv (b : Block) (c : Config M) : Prop :=
  Issued c.mem b ∧ b ∉ c.cont.frameBlocks

theorem execAssign_ok {p : Program} {env : Env} {m m' : M} {lv : LExpr} {e : Expr}
    {evs : List Event} (h : execAssign p env m lv e = (evs, .ok m')) :
    ∃ b v, store m b v = some m' ∧ Event.write b ∈ evs := by
  unfold execAssign at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · next b _ _ m'' hs =>
        simp only [Prod.mk.injEq, Except.ok.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨b, _, hs, by simp⟩
      · cases h

theorem execCall_ok {p : Program} {env : Env} {m : M} {dst : Option Var} {f : FunName}
    {args : List Expr} {evs : List Event} {ce : CallEntry M}
    (h : execCall p env m dst f args = (evs, .ok ce)) :
    ∃ vs, createAll m vs = (ce.locals, ce.mem) := by
  unfold execCall at h
  split at h
  · cases h
  · split at h
    · split at h
      · simp only [Prod.mk.injEq, Except.ok.injEq] at h
        obtain ⟨-, rfl⟩ := h
        exact ⟨_, rfl⟩
      · cases h
    · cases h

/-- A fault keeps the memory and has no call frame. -/
theorem frameInv_fault {b : Block} {m : M} {l : Label} {a : Alarm} (h : Issued m b) :
    FrameInv b (Config.fault l a m) ∧ load (Config.fault l a m).mem b = load m b :=
  ⟨⟨h, by simp [Config.cont, Cont.frameBlocks]⟩, rfl⟩

theorem stepStmt_preserves {p : Program} {s : Stmt} {k : Cont} {env : Env} {m : M}
    {evs : List Event} {c' : Config M} {b : Block}
    (h : stepStmt p s k env m = (evs, c')) (hiss : Issued m b) (hfr : b ∉ k.frameBlocks)
    (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    FrameInv b c' ∧ load c'.mem b = load m b := by
  cases s with
  | skip l =>
    simp only [stepStmt, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact ⟨⟨hiss, hfr⟩, rfl⟩
  | assign l lv e =>
    simp only [stepStmt] at h
    split at h
    · next evs' m' hexec =>
      simp only [Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      obtain ⟨b', v, hs, hmem⟩ := execAssign_ok hexec
      have hne : b ≠ b' := by
        intro heq
        exact hw _ hmem (by simp [Event.Writes, heq])
      exact ⟨⟨issued_store hs hiss, hfr⟩, load_store_other hs hne⟩
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact frameInv_fault hiss
  | seq l s₁ s₂ =>
    simp only [stepStmt, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact ⟨⟨hiss, by simpa [Config.cont, Cont.frameBlocks] using hfr⟩, rfl⟩
  | ite l c s₁ s₂ =>
    simp only [stepStmt] at h
    split at h
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact ⟨⟨hiss, hfr⟩, rfl⟩
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact frameInv_fault hiss
  | loop l c body =>
    simp only [stepStmt] at h
    split at h
    · split at h
      · simp only [Prod.mk.injEq] at h
        obtain ⟨-, rfl⟩ := h
        exact ⟨⟨hiss, by simpa [Config.cont, Cont.frameBlocks] using hfr⟩, rfl⟩
      · simp only [Prod.mk.injEq] at h
        obtain ⟨-, rfl⟩ := h
        exact ⟨⟨hiss, hfr⟩, rfl⟩
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact frameInv_fault hiss
  | call l dst f args =>
    simp only [stepStmt] at h
    split at h
    · next evs' ce hexec =>
      simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      obtain ⟨vs, hc⟩ := execCall_ok hexec
      obtain ⟨h₁, h₂, h₃⟩ := createAll_issued (m := m) vs hiss
      rw [hc] at h₁ h₂ h₃
      refine ⟨⟨h₂, ?_⟩, h₁⟩
      simp only [Config.cont, Cont.frameBlocks, List.mem_append, not_or]
      exact ⟨h₃, hfr⟩
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact frameInv_fault hiss
  | ret l e =>
    cases e with
    | none =>
      simp only [stepStmt, Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact ⟨⟨hiss, hfr⟩, rfl⟩
    | some e =>
      simp only [stepStmt] at h
      split at h
      · simp only [Prod.mk.injEq] at h
        obtain ⟨-, rfl⟩ := h
        exact ⟨⟨hiss, hfr⟩, rfl⟩
      · simp only [Prod.mk.injEq] at h
        obtain ⟨-, rfl⟩ := h
        exact frameInv_fault hiss
  | assert l e =>
    simp only [stepStmt, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact ⟨⟨hiss, hfr⟩, rfl⟩

theorem stepNext_preserves {k : Cont} {env : Env} {m : M} {b : Block}
    (hiss : Issued m b) (hfr : b ∉ k.frameBlocks) :
    FrameInv b (stepNext k env m) ∧ load (stepNext k env m).mem b = load m b := by
  cases k with
  | stop => exact ⟨⟨hiss, by simp [stepNext, Config.cont, Cont.frameBlocks]⟩, rfl⟩
  | seq s k => exact ⟨⟨hiss, by simpa [Config.cont, Cont.frameBlocks] using hfr⟩, rfl⟩
  | loop l c body k => exact ⟨⟨hiss, by simpa [Config.cont, Cont.frameBlocks] using hfr⟩, rfl⟩
  | call site dst env' locals k => exact ⟨⟨hiss, hfr⟩, rfl⟩

theorem stepRet_preserves {v : Option Value} {k : Cont} {m : M} {evs : List Event}
    {c' : Config M} {b : Block}
    (h : stepRet v k m = (evs, c')) (hiss : Issued m b) (hfr : b ∉ k.frameBlocks)
    (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    FrameInv b c' ∧ load c'.mem b = load m b := by
  cases k with
  | stop =>
    simp only [stepRet, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact ⟨⟨hiss, by simp [Config.cont, Cont.frameBlocks]⟩, rfl⟩
  | seq s k =>
    simp only [stepRet, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact ⟨⟨hiss, by simpa [Config.cont, Cont.frameBlocks] using hfr⟩, rfl⟩
  | loop l c body k =>
    simp only [stepRet, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact ⟨⟨hiss, by simpa [Config.cont, Cont.frameBlocks] using hfr⟩, rfl⟩
  | call site dst env' locals k =>
    simp only [Cont.frameBlocks, List.mem_append, not_or] at hfr
    obtain ⟨hloc, hk⟩ := hfr
    obtain ⟨hl₁, hi₁⟩ := releaseAll_other (m := m) locals hloc hiss
    simp only [stepRet] at h
    split at h
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact ⟨⟨hi₁, hk⟩, hl₁⟩
    · simp only [Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      exact ⟨⟨hi₁, by simp [Config.cont, Cont.frameBlocks]⟩, hl₁⟩
    · next b' v' =>
      split at h
      · next m₂ hs =>
        simp only [Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        have hne : b ≠ b' := by
          intro heq
          exact hw (.write b') (by simp) (by simp [Event.Writes, heq])
        exact ⟨⟨issued_store hs hi₁, hk⟩, (load_store_other hs hne).trans hl₁⟩
      · simp only [Prod.mk.injEq] at h
        obtain ⟨-, rfl⟩ := h
        exact ⟨⟨hi₁, by simp [Config.cont, Cont.frameBlocks]⟩, hl₁⟩

/-- One step that does not write `b` keeps the invariant and the value of
`b`. -/
theorem step_preserves {p : Program} {c c' : Config M} {evs : List Event} {b : Block}
    (h : step p c = some (evs, c')) (hinv : FrameInv b c)
    (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    FrameInv b c' ∧ load c'.mem b = load c.mem b := by
  obtain ⟨hiss, hfr⟩ := hinv
  cases c with
  | run s k env m =>
    simp only [step, Option.some.injEq] at h
    exact stepStmt_preserves h hiss hfr hw
  | next k env m =>
    simp only [step, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact stepNext_preserves hiss hfr
  | ret v k m =>
    simp only [step, Option.some.injEq] at h
    exact stepRet_preserves h hiss hfr hw
  | done o m => simp [step] at h
  | fault l a m => simp [step] at h

/-- A finite sequence of steps that does not write `b` keeps the value of
`b`. -/
theorem steps_preserves {p : Program} {c c' : Config M} {evs : List Event} {b : Block}
    (h : Steps p c evs c') (hinv : FrameInv b c) (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    load c'.mem b = load c.mem b := by
  induction h with
  | refl c => rfl
  | @head c₁ c₂ c₃ evs₁ evs₂ hstep _ ih =>
    have hw₁ : ∀ e ∈ evs₁, ¬ e.Writes b := fun e he => hw e (List.mem_append_left _ he)
    have hw₂ : ∀ e ∈ evs₂, ¬ e.Writes b := fun e he => hw e (List.mem_append_right _ he)
    obtain ⟨hinv', hval⟩ := step_preserves hstep hinv hw₁
    exact (ih hinv' hw₂).trans hval

/-- General form of the frame lemma. Let `b` be a block issued before the
execution of `s` from `σ`. At every configuration of a finite prefix that does
not write `b`, `b` has the value it had at entry. -/
theorem frame_of_not_written {p : Program} {s : Stmt} {σ : State M} {b : Block}
    (hb : Issued σ.mem b) {evs : List Event} {c : Config M}
    (hpre : Prefix p s σ evs c) (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    load c.mem b = load σ.mem b :=
  steps_preserves hpre ⟨hb, by simp [Config.entry, Config.cont, Cont.frameBlocks]⟩ hw

/-- **Frame lemma without sweeps.** Let `b` be a block that exists when `s`
starts from `σ`, and that no finite prefix of the execution of `s` from `σ`
reads or writes. At every visit inside `s`, `b` has the value it had at
entry. -/
theorem frame_lemma {p : Program} {s : Stmt} {σ : State M} {b : Block}
    (hlive : Live σ.mem b) (hframe : InFrame p s σ b)
    {l : Label} {env : Env} {m : M} (hvisit : Visit p s σ l env m) :
    load m b = load σ.mem b := by
  obtain ⟨evs, st, k, hpre, -⟩ := hvisit
  exact frame_of_not_written hlive.issued hpre
    fun e he hwr => hframe evs _ hpre e he (Event.accesses_of_writes hwr)

end

end ReuseModel
