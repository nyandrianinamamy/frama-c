import ReuseModel.Observations

/-!
# Frame lemma with lexical scope sweeps

An entry block untouched by ordinary writes changes only as recorded lexical
sweeps mark its pointers. Each sweep targets a local allocated inside the
execution. If the entry value's pointer target was already issued at entry,
the sweep cannot change that value.
-/

namespace ReuseModel

open Memory

/-- The blocks held as locals by the call and scope frames of a continuation. -/
def Cont.frameBlocks : Cont → List Block
  | .stop => []
  | .seq _ k => k.frameBlocks
  | .loop _ _ _ k => k.frameBlocks
  | .call _ _ _ locals k | .scope locals _ k => locals ++ k.frameBlocks

/-- The targets of the lexical sweeps in a prefix, in execution order. -/
def sweepTargets (evs : List Event) : List Block :=
  evs.filterMap fun e => match e with
    | .sweep b => some b
    | _ => none

@[simp] private theorem sweepTargets_append (es fs : List Event) :
    sweepTargets (es ++ fs) = sweepTargets es ++ sweepTargets fs :=
  List.filterMap_append

@[simp] private theorem sweepTargets_read (b : Block) :
    sweepTargets [.read b] = [] := rfl

@[simp] private theorem sweepTargets_write (b : Block) :
    sweepTargets [.write b] = [] := rfl

@[simp] private theorem sweepTargets_enter (bs : List Block) :
    sweepTargets (bs.map Event.scopeEnter) = [] := by
  induction bs <;> simp_all [sweepTargets]

@[simp] private theorem sweepTargets_exit (bs : List Block) :
    sweepTargets (bs.map Event.scopeExit) = [] := by
  induction bs <;> simp_all [sweepTargets]

@[simp] private theorem sweepTargets_sweep (bs : List Block) :
    sweepTargets (bs.map Event.sweep) = bs := by
  induction bs <;> simp_all [sweepTargets]

section
variable {M : Type} [Memory M]

/-- `b` is in the frame of the statement of `t` from `σ`: no finite prefix of
its execution from `σ` reads or writes `b`. -/
def InFrame (t : Subject) (σ : State M) (b : Block) : Prop :=
  ∀ evs c, Prefix t σ evs c → ∀ e ∈ evs, ¬ e.Accesses b

/-- Invariant of the proof: `b` has been issued, and no call frame of the
configuration holds `b` as a local. -/
def FrameInv (b : Block) (c : Config M) : Prop :=
  Issued c.mem b ∧ b ∉ c.cont.frameBlocks

@[simp] private theorem sweepTargets_expr (p : Program) (env : Env) (m : M)
    (e : Expr) : sweepTargets (evalExpr p env m e).1 = [] := by
  induction e with
  | const => rfl
  | addr | var => simp only [evalExpr]; split <;> rfl
  | deref e ih =>
    simp only [evalExpr]
    split <;> rename_i he <;> rw [he] at ih
    · change sweepTargets _ = [] at ih
      simp [ih]
    · exact ih
    · exact ih
  | binop op e₁ e₂ ih₁ ih₂ =>
    simp only [evalExpr]
    split <;> rename_i he <;> rw [he] at ih₁
    · exact ih₁
    · split <;> rename_i he' <;> rw [he'] at ih₂ <;> simp [ih₁, ih₂]

@[simp] private theorem sweepTargets_lexpr (p : Program) (env : Env) (m : M)
    (e : LExpr) : sweepTargets (evalLExpr p env m e).1 = [] := by
  cases e with
  | var => simp only [evalLExpr]; split <;> rfl
  | deref e =>
    simp only [evalLExpr]
    split <;> rename_i he <;> simpa only [he] using sweepTargets_expr p env m e

@[simp] private theorem sweepTargets_args (p : Program) (env : Env) (m : M)
    (es : List Expr) : sweepTargets (evalArgs p env m es).1 = [] := by
  induction es with
  | nil => rfl
  | cons e es ih =>
    have he := sweepTargets_expr p env m e
    simp only [evalArgs]
    split <;> rename_i h <;> rw [h] at he
    · exact he
    · split <;> rename_i ht <;> rw [ht] at ih <;> simp [he, ih]

@[simp] private theorem sweepTargets_assign (p : Program) (env : Env) (m : M)
    (lv : LExpr) (e : Expr) : sweepTargets (execAssign p env m lv e).1 = [] := by
  have he := sweepTargets_expr p env m e
  have hl := sweepTargets_lexpr p env m lv
  simp only [execAssign]
  split <;> rename_i h <;> rw [h] at he
  · exact he
  · split <;> rename_i h' <;> rw [h'] at hl
    · simp [he, hl]
    · split <;> simp [he, hl]

@[simp] private theorem sweepTargets_call (p : Program) (env : Env) (m : M)
    (dst : Option Var) (f : FunName) (args : List Expr) :
    sweepTargets (execCall p env m dst f args).1 = [] := by
  have he := sweepTargets_args p env m args
  simp only [execCall]
  split <;> rename_i h <;> rw [h] at he
  · exact he
  · split
    · split <;> simp [he]
    · exact he

private theorem sweepAll_other {m : M} {b : Block} (bs : List Block)
    (hb : b ∉ bs) (hi : Issued m b) :
    Issued (sweepAll m bs) b ∧
      load (sweepAll m bs) b = applySweeps bs (load m b) := by
  induction bs generalizing m with
  | nil => exact ⟨hi, rfl⟩
  | cons a bs ih =>
    simp only [List.mem_cons, not_or] at hb
    obtain ⟨hne, hmem⟩ := hb
    obtain ⟨hi', hv⟩ := ih hmem (issued_sweep m a b hi)
    exact ⟨hi', by simpa [sweepAll, applySweeps, load_sweep_other m a b hne] using hv⟩

/-- The invariant and single-block effect of a step, with the freshness of
its sweep targets relative to any block tracked by the invariant. -/
private def FrameStep (b : Block) (m : M) (evs : List Event) (c : Config M) : Prop :=
  FrameInv b c ∧ b ∉ sweepTargets evs ∧
    ((∀ e ∈ evs, ¬ e.Writes b) →
      load c.mem b = applySweeps (sweepTargets evs) (load m b))

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

private theorem frameStep_plain {b : Block} {m : M} {evs : List Event}
    {c : Config M} (hi : FrameInv b c) (hs : sweepTargets evs = [])
    (hv : (∀ e ∈ evs, ¬ e.Writes b) → load c.mem b = load m b) :
    FrameStep b m evs c := by
  exact ⟨hi, by simp [hs], by simpa [hs, applySweeps] using hv⟩

private theorem frameInv_fault {b : Block} {m : M} {l : Label} {a : Alarm}
    (h : Issued m b) : FrameInv b (Config.fault l a m) :=
  ⟨h, by simp [Config.cont, Cont.frameBlocks]⟩

private theorem stepStmt_preserves {p : Program} {s : Stmt} {k : Cont}
    {env : Env} {m : M} {b : Block}
    (hi : Issued m b) (hf : b ∉ k.frameBlocks) :
    FrameStep b m (stepStmt p s k env m).1 (stepStmt p s k env m).2 := by
  cases s with
  | skip => exact frameStep_plain ⟨hi, hf⟩ rfl (fun _ => rfl)
  | seq =>
    exact frameStep_plain ⟨hi, by simpa [stepStmt, Config.cont, Cont.frameBlocks] using hf⟩
      rfl (fun _ => rfl)
  | assign l lv e =>
    have hsw := sweepTargets_assign p env m lv e
    simp only [stepStmt]
    split <;> rename_i h <;> rw [h] at hsw
    · obtain ⟨b', v, hs, he⟩ := execAssign_ok h
      refine frameStep_plain ⟨issued_store hs hi, hf⟩ hsw (fun hw => ?_)
      apply load_store_other hs
      rintro rfl
      exact hw _ he rfl
    · exact frameStep_plain (frameInv_fault hi) hsw (fun _ => rfl)
  | ite l e s₁ s₂ =>
    have hsw := sweepTargets_expr p env m e
    simp only [stepStmt]
    split <;> rename_i h <;> rw [h] at hsw
    · exact frameStep_plain ⟨hi, hf⟩ hsw (fun _ => rfl)
    · exact frameStep_plain (frameInv_fault hi) hsw (fun _ => rfl)
  | loop l e body =>
    have hsw := sweepTargets_expr p env m e
    simp only [stepStmt]
    split <;> rename_i h <;> rw [h] at hsw
    · split
      · exact frameStep_plain
          ⟨hi, by simpa [Config.cont, Cont.frameBlocks] using hf⟩ hsw (fun _ => rfl)
      · exact frameStep_plain ⟨hi, hf⟩ hsw (fun _ => rfl)
    · exact frameStep_plain (frameInv_fault hi) hsw (fun _ => rfl)
  | call l dst f args =>
    have hsw := sweepTargets_call p env m dst f args
    simp only [stepStmt]
    split <;> rename_i h <;> rw [h] at hsw
    · obtain ⟨vs, hc⟩ := execCall_ok h
      obtain ⟨hv, hi', hloc⟩ := createAll_issued (m := m) vs hi
      rw [hc] at hv hi' hloc
      exact frameStep_plain
        ⟨hi', by simp [Config.cont, Cont.frameBlocks, hloc, hf]⟩ hsw (fun _ => hv)
    · exact frameStep_plain (frameInv_fault hi) hsw (fun _ => rfl)
  | scope l locals body =>
    obtain ⟨hv, hi', hloc⟩ := createAll_issued (locals.map fun x => Value.int x.2) hi
    exact frameStep_plain
      ⟨hi', by simp [stepStmt, Config.cont, Cont.frameBlocks, hloc, hf]⟩
      (sweepTargets_enter _) (fun _ => hv)
  | ret l e =>
    cases e with
    | none => exact frameStep_plain ⟨hi, hf⟩ rfl (fun _ => rfl)
    | some e =>
      have hsw := sweepTargets_expr p env m e
      simp only [stepStmt]
      split <;> rename_i h <;> rw [h] at hsw
      · exact frameStep_plain ⟨hi, hf⟩ hsw (fun _ => rfl)
      · exact frameStep_plain (frameInv_fault hi) hsw (fun _ => rfl)
  | assert l e => exact frameStep_plain ⟨hi, hf⟩ (sweepTargets_expr p env m e) (fun _ => rfl)

private theorem frameStep_sweep {b : Block} {m : M} {bs : List Block} {c : Config M}
    (hi : Issued m b) (hloc : b ∉ bs) (hf : b ∉ c.cont.frameBlocks)
    (hc : c.mem = sweepAll m bs) : FrameStep b m (bs.map Event.sweep) c := by
  obtain ⟨hi', hv⟩ := sweepAll_other bs hloc hi
  exact ⟨⟨hc ▸ hi', hf⟩, by simpa using hloc, fun _ => by simpa [hc] using hv⟩

private theorem stepNext_preserves {k : Cont} {env : Env} {m : M} {b : Block}
    (hi : Issued m b) (hf : b ∉ k.frameBlocks) :
    FrameStep b m (stepNext k env m).1 (stepNext k env m).2 := by
  cases k with
  | scope bs env k =>
    simp only [Cont.frameBlocks, List.mem_append, not_or] at hf
    obtain ⟨hloc, hk⟩ := hf
    exact frameStep_sweep hi hloc hk rfl
  | _ =>
    exact frameStep_plain ⟨hi, hf⟩
      rfl (fun _ => rfl)

private theorem stepRet_preserves {v : Option Value} {k : Cont} {m : M} {b : Block}
    (hi : Issued m b) (hf : b ∉ k.frameBlocks) :
    FrameStep b m (stepRet v k m).1 (stepRet v k m).2 := by
  cases k with
  | scope bs env k =>
    simp only [Cont.frameBlocks, List.mem_append, not_or] at hf
    obtain ⟨hloc, hk⟩ := hf
    exact frameStep_sweep hi hloc hk rfl
  | call site dst env bs k =>
    simp only [Cont.frameBlocks, List.mem_append, not_or] at hf
    obtain ⟨hloc, hk⟩ := hf
    obtain ⟨hv, hi'⟩ := releaseAll_other (m := m) bs hloc hi
    simp only [stepRet]
    split
    · exact frameStep_plain ⟨hi', hk⟩ (sweepTargets_exit bs) (fun _ => hv)
    · exact frameStep_plain (frameInv_fault hi') (sweepTargets_exit bs) (fun _ => hv)
    · next b' v' =>
      split
      · next m' hs =>
        refine frameStep_plain ⟨issued_store hs hi', hk⟩ (by simp)
          (fun hw => (load_store_other hs ?_).trans hv)
        rintro rfl
        exact hw (.write b) (by simp) rfl
      · exact frameStep_plain (frameInv_fault hi') (by simp) (fun _ => hv)
  | _ =>
    exact frameStep_plain ⟨hi, hf⟩
      rfl (fun _ => rfl)

private theorem step_preserves {p : Program} {c c' : Config M} {evs : List Event}
    {b : Block} (h : step p c = some (evs, c')) (hi : FrameInv b c) :
    FrameStep b c.mem evs c' := by
  obtain ⟨hiss, hf⟩ := hi
  cases c with
  | run s k env m =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
    exact stepStmt_preserves hiss hf
  | next k env m =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
    exact stepNext_preserves hiss hf
  | ret v k m =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
    exact stepRet_preserves hiss hf
  | done | fault => contradiction

private theorem steps_preserves {p : Program} {c c' : Config M} {evs : List Event}
    {b : Block} (h : Steps p c evs c') (hi : FrameInv b c) :
    b ∉ sweepTargets evs ∧
      ((∀ e ∈ evs, ¬ e.Writes b) →
        load c'.mem b = applySweeps (sweepTargets evs) (load c.mem b)) := by
  induction h with
  | refl => exact ⟨by simp [sweepTargets], fun _ => rfl⟩
  | @head c₁ c₂ c₃ es fs hs _ ih =>
    obtain ⟨hi', hbs, hv⟩ := step_preserves hs hi
    obtain ⟨hbf, hv'⟩ := ih hi'
    refine ⟨by simp [hbs, hbf], fun hw => ?_⟩
    rw [hv' (fun e he => hw e (List.mem_append_right _ he)),
      hv (fun e he => hw e (List.mem_append_left _ he))]
    simp only [sweepTargets_append, applySweeps, List.foldl_append]

/-- At every prefix, an entry block untouched by writes has its entry value
transformed by the recorded lexical sweeps. -/
theorem frame_of_not_written {p : Program} {s : Stmt} {σ : State M} {b : Block}
    (hb : Issued σ.mem b) {evs : List Event} {c : Config M}
    (hpre : Steps p (Config.entry s σ) evs c) (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    load c.mem b = applySweeps (sweepTargets evs) (load σ.mem b) :=
  (steps_preserves hpre ⟨hb, by simp [Config.entry, Config.cont, Cont.frameBlocks]⟩).2 hw

/-- Each recorded sweep targets a local allocated during execution of the
statement. Issued block identities are never used again. -/
theorem sweep_target_fresh {t : Subject} {σ : State M} {evs : List Event} {c : Config M}
    (hpre : Prefix t σ evs c) {target : Block} (ht : target ∈ sweepTargets evs) :
    ¬ Issued σ.mem target :=
  fun hi => (steps_preserves hpre ⟨hi, by simp [Config.entry, Config.cont, Cont.frameBlocks]⟩).1 ht

/-- At any finite prefix of a subject, a live frame block keeps its entry
value up to the recorded lexical sweeps. This includes visits and exits. -/
theorem frame_lemma {t : Subject} {σ : State M} {b : Block}
    (hlive : Live σ.mem b) (hframe : InFrame t σ b)
    {evs : List Event} {c : Config M} (hpre : Prefix t σ evs c) :
    load c.mem b = applySweeps (sweepTargets evs) (load σ.mem b) :=
  frame_of_not_written hlive.issued hpre
    fun e he hw => hframe evs c hpre e he (Event.accesses_of_writes hw)

/-- A sweep changes a surviving value exactly when it is an unmarked pointer
to one of the recorded targets. -/
theorem applySweeps_eq_iff (targets : List Block) (v : Option Value) :
    applySweeps targets v = v ↔ ∀ target ∈ targets, v ≠ some (.ptr target) := by
  have escaped (bs : List Block) (b : Block) :
      applySweeps bs (some (.escaped b)) = some (.escaped b) := by
    induction bs with
    | nil => rfl
    | cons a bs ih =>
      change applySweeps bs (some (Value.escape a (.escaped b))) = _
      simpa [Value.escape] using ih
  induction targets with
  | nil => simp [applySweeps]
  | cons b bs ih =>
    by_cases h : v = some (.ptr b)
    · subst v
      change applySweeps bs (some (Value.escape b (.ptr b))) = _ ↔ _
      simp [Value.escape, escaped]
    · have he : v.map (Value.escape b) = v := by
        cases v <;> simp_all [Value.escape]
      change applySweeps bs (v.map (Value.escape b)) = v ↔ _
      simp [he, ih, h]

/-- No frame rewrite is needed if the current entry holder cannot point
unmarked to an unissued block. The prefix need only exclude ordinary writes
to the holder. -/
theorem frame_no_sweep_rewrite {t : Subject} {σ : State M} {b : Block}
    (hb : Issued σ.mem b)
    (hptr : ∀ target, load σ.mem b = some (.ptr target) → Issued σ.mem target)
    {evs : List Event} {c : Config M} (hpre : Prefix t σ evs c)
    (hw : ∀ e ∈ evs, ¬ e.Writes b) :
    load c.mem b = load σ.mem b := by
  rw [frame_of_not_written hb hpre hw]
  exact (applySweeps_eq_iff _ _).2 fun target ht hload =>
    sweep_target_fresh hpre ht (hptr target hload)


-- While an initially absent block is live, it must belong to an active
-- lexical or call frame. A fault has no continuation to unwind.
private def AbsentOutsideLocals (b : Block) (c : Config M) : Prop :=
  match c with
  | .fault .. => True
  | _ => b ∉ c.cont.frameBlocks → load c.mem b = none

private theorem createAll_other {m : M} {b : Block} (vs : List Value)
    (hb : b ∉ (createAll m vs).1) : load (createAll m vs).2 b = load m b := by
  induction vs generalizing m with
  | nil => rfl
  | cons v vs ih =>
    simp only [createAll, List.mem_cons, not_or] at hb
    exact (ih hb.2).trans (load_create_other m v b hb.1)

private theorem store_preserves_absence {m m' : M} {b dst : Block} {v : Value}
    (hs : store m dst v = some m') (h : load m b = none) : load m' b = none := by
  by_cases he : b = dst
  · subst dst
    have hok := store_ok_iff (m := m) (b := b) (v := v)
    rw [hs, h] at hok
    contradiction
  · rw [load_store_other hs he, h]

private theorem releaseAll_absence {m : M} {b : Block} (bs : List Block)
    (h : b ∈ bs ∨ load m b = none) : load (releaseAll m bs) b = none := by
  induction bs generalizing m with
  | nil => simpa [releaseAll] using h
  | cons a bs ih =>
    change load (releaseAll (release m a) bs) b = none
    by_cases he : b = a
    · subst a
      exact ih (Or.inr (load_release_same _ _))
    · apply ih
      simpa [he, Ne.symm he, load_release_other m a b he] using h

private theorem sweepAll_absence {m : M} {b : Block} (bs : List Block)
    (h : b ∈ bs ∨ load m b = none) : load (sweepAll m bs) b = none := by
  induction bs generalizing m with
  | nil => simpa [sweepAll] using h
  | cons a bs ih =>
    change load (sweepAll (sweep m a) bs) b = none
    by_cases he : b = a
    · subst a
      exact ih (Or.inr (load_sweep_same _ _))
    · apply ih
      simpa [he, Ne.symm he, load_sweep_other m a b he] using h

private theorem absence_at_pop {m : M} {b : Block} {bs : List Block} {k : Cont}
    (h : b ∉ bs ++ k.frameBlocks → load m b = none)
    (hk : b ∉ k.frameBlocks) : b ∈ bs ∨ load m b = none := by
  by_cases hb : b ∈ bs
  · exact Or.inl hb
  · exact Or.inr (h (by simp [hb, hk]))

private theorem stmt_preserves_absence {p : Program} {s : Stmt} {k : Cont}
    {env : Env} {m : M} {b : Block} (h : b ∉ k.frameBlocks → load m b = none) :
    AbsentOutsideLocals b (stepStmt p s k env m).2 := by
  cases s with
  | skip | seq | assert => exact h
  | assign l lv e =>
    simp only [stepStmt]
    split
    · next evs m' hs =>
      obtain ⟨dst, v, hstore, -⟩ := execAssign_ok hs
      exact fun hb => store_preserves_absence hstore (h hb)
    · trivial
  | ite =>
    simp only [stepStmt]
    split
    · exact h
    · trivial
  | loop =>
    simp only [stepStmt]
    split
    · split <;> exact h
    · trivial
  | ret l e =>
    cases e with
    | none => exact h
    | some e =>
      simp only [stepStmt]
      split
      · exact h
      · trivial
  | scope l locals body =>
    intro hb
    simp only [stepStmt, Config.cont, Cont.frameBlocks, List.mem_append, not_or] at hb
    exact (createAll_other _ hb.1).trans (h hb.2)
  | call l dst f args =>
    simp only [stepStmt]
    split
    · next evs ce hc =>
      obtain ⟨vs, hcreate⟩ := execCall_ok hc
      intro hb
      simp only [Config.cont, Cont.frameBlocks, List.mem_append, not_or] at hb
      have he : ∀ r : List Block × M, createAll m vs = r →
          b ∉ r.1 → load r.2 b = load m b := by
        rintro _ rfl
        exact createAll_other vs
      exact (he _ hcreate hb.1).trans (h hb.2)
    · trivial

private theorem step_preserves_absence {p : Program} {c c' : Config M}
    {evs : List Event} {b : Block} (hs : step p c = some (evs, c'))
    (h : AbsentOutsideLocals b c) : AbsentOutsideLocals b c' := by
  cases c with
  | run s k env m =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj hs)
    exact stmt_preserves_absence h
  | next k env m =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj hs)
    cases k with
    | stop => exact fun _ => h (by simp [Config.cont, Cont.frameBlocks])
    | scope bs _ k => exact fun hk => sweepAll_absence bs (absence_at_pop h hk)
    | _ => exact h
  | ret v k m =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj hs)
    cases k with
    | stop => exact fun _ => h (by simp [Config.cont, Cont.frameBlocks])
    | scope bs _ k => exact fun hk => sweepAll_absence bs (absence_at_pop h hk)
    | call site dst env bs k =>
      dsimp only [stepRet]
      split
      · exact fun hk => releaseAll_absence bs (absence_at_pop h hk)
      · trivial
      · split
        · next m' hstore =>
          exact fun hk => store_preserves_absence hstore
            (releaseAll_absence bs (absence_at_pop h hk))
        · trivial
    | _ => exact h
  | done | fault => contradiction

/-- A block absent at entry is absent on normal exit. Stores cannot create
bindings and every local created inside the statement has been released. -/
theorem exit_preserves_absence {t : Subject} {σ : State M} {b : Block}
    (hb : load σ.mem b = none) {evs : List Event} {o : Outcome} {out : M}
    (hp : Prefix t σ evs (.done o out)) : load out b = none := by
  have preserve {c c' : Config M} {evs : List Event} (h : Steps t.prog c evs c') :
      AbsentOutsideLocals b c → AbsentOutsideLocals b c' := by
    induction h with
    | refl => exact id
    | head hs _ ih => exact fun h => ih (step_preserves_absence hs h)
  exact preserve hp (fun _ => hb) (by simp [Config.cont, Cont.frameBlocks])

end

end ReuseModel
