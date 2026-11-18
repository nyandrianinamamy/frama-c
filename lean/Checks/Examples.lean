import ReuseModel
import Checks.AxiomCheck

/-!
# Worked examples

Three small programs, run with the memory `FunMem`, and the body of a
function of the third as a fourth observed statement. Each program and its
observed statement form a `Subject`, whose fragment conditions are checked by
`decide`. Each fact is computed by the Lean kernel from the execution (`run`)
and turned into an observation by the lemmas of the first section.

* Aliasing: two pointers to the same existing block; a write through one is
  read through the other.
* Lifetime: a callee returns the address of its local; the caller's
  dereference after the return faults, and the block that holds the pointer
  still holds it.
* A call that does not return: Reach and Safety observe visits inside it, and
  the frame lemma applies to a global that the call does not access.
* The body of the function of the previous program as the subject: Reach and
  Safety observe the statements of the body.

The last section evaluates comparisons with the null pointer.
-/

namespace Checks

open ReuseModel Memory

/-! ## Reading observations off the execution -/

section
variable {M : Type} [Memory M]

/-- The label of the statement about to execute. -/
def labelOf? : Config M → Option Label
  | .run s _ _ _ => some s.label
  | _ => none

/-- The alarm that stopped the execution, with the label that raised it. -/
def faultOf? : Config M → Option (Label × Alarm)
  | .fault l a _ => some (l, a)
  | _ => none

/-- How the statement ended. -/
def outcomeOf? : Config M → Option Outcome
  | .done o _ => some o
  | _ => none

/-- The assertion about to be visited, and whether it holds. -/
def assertionOf? (p : Program) : Config M → Option (Label × Bool)
  | .run (.assert l e) _ env m => some (l, assertionHolds p env m e)
  | _ => none

theorem visit_of_run {t : Subject} {σ : State M} {n : Nat} {l : Label}
    (h : labelOf? (run t.prog n (Config.entry t.stmt σ)).2 = some l) :
    ∃ env, Visit t σ l env (run t.prog n (Config.entry t.stmt σ)).2.mem := by
  have hs := run_steps t.prog n (Config.entry t.stmt σ)
  revert h hs
  cases (run t.prog n (Config.entry t.stmt σ)).2 with
  | run st k env m =>
    intro h hs
    simp only [labelOf?, Option.some.injEq] at h
    exact ⟨env, _, st, k, hs, h⟩
  | _ => intro h; simp [labelOf?] at h

theorem alarm_of_run {t : Subject} {σ : State M} {n : Nat} {l : Label}
    {a : Alarm} (h : faultOf? (run t.prog n (Config.entry t.stmt σ)).2 = some (l, a)) :
    AlarmRaised t σ l a := by
  have hs := run_steps t.prog n (Config.entry t.stmt σ)
  revert h hs
  cases (run t.prog n (Config.entry t.stmt σ)).2 with
  | fault l' a' m =>
    intro h hs
    simp only [faultOf?, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨_, m, hs⟩
  | _ => intro h; simp [faultOf?] at h

theorem exit_of_run {t : Subject} {σ : State M} {n : Nat} {o : Outcome}
    (h : outcomeOf? (run t.prog n (Config.entry t.stmt σ)).2 = some o) :
    Exit t σ o (run t.prog n (Config.entry t.stmt σ)).2.mem := by
  have hs := run_steps t.prog n (Config.entry t.stmt σ)
  revert h hs
  cases (run t.prog n (Config.entry t.stmt σ)).2 with
  | done o' m =>
    intro h hs
    simp only [outcomeOf?, Option.some.injEq] at h
    subst h
    exact ⟨_, hs⟩
  | _ => intro h; simp [outcomeOf?] at h

theorem assertionFails_of_run {t : Subject} {σ : State M} {n : Nat} {l : Label}
    (h : assertionOf? t.prog (run t.prog n (Config.entry t.stmt σ)).2 =
      some (l, false)) :
    AssertionFails t σ l := by
  have hs := run_steps t.prog n (Config.entry t.stmt σ)
  revert h hs
  cases (run t.prog n (Config.entry t.stmt σ)).2 with
  | run st k env m =>
    cases st with
    | assert l' e =>
      intro h hs
      simp only [assertionOf?, Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, hf⟩ := h
      exact ⟨_, e, k, env, m, hs, hf⟩
    | _ => intro h; simp [assertionOf?] at h
  | _ => intro h; simp [assertionOf?] at h

end

/-- A memory whose blocks `0, 1, …` hold the given values. -/
def memOf (vs : List Value) : FunMem := (createAll FunMem.empty vs).2

/-- The state of a statement run at top level: no local, the given memory. -/
def topState (vs : List Value) : State FunMem := ⟨fun _ => none, memOf vs⟩

/-! ## Aliasing

Globals `g`, `p`, `q` in blocks 0, 1, 2; `p` and `q` both point to `g`.

```
L1: { L2: *p = 7;  L3: assert (*q == 7); }
```
-/

def aliasProg : Program where
  funs := []
  globals := fun x =>
    if x = "g" then some 0 else if x = "p" then some 1 else if x = "q" then some 2
    else none

def aliasStmt : Stmt :=
  .seq 1 (.assign 2 (.deref (.var "p")) (.const 7))
    (.assert 3 (.binop .eq (.deref (.var "q")) (.const 7)))

/-- The program has no function; the labels 1, 2, 3 are distinct. -/
def aliasSubj : Subject where
  prog := aliasProg
  stmt := aliasStmt
  wf := ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩

def aliasState : State FunMem := topState [.int 0, .ptr 0, .ptr 0]

/-- The assertion is visited and holds there. -/
example : assertionOf? aliasProg (run aliasProg 3 (Config.entry aliasStmt aliasState)).2 =
    some (3, true) := by decide

/-- The statement completes, with `g` equal to 7. -/
example : Exit aliasSubj aliasState .completed
    (run aliasProg 5 (Config.entry aliasStmt aliasState)).2.mem ∧
    load (run aliasProg 5 (Config.entry aliasStmt aliasState)).2.mem 0 = some (.int 7) :=
  ⟨exit_of_run (by decide), by decide⟩

/-! ## Lifetime of a callee's local

Globals `p`, `y` in blocks 0, 1. The function `leak` returns the address of
its local `x`.

```
int *leak(void) { int x = 5; L10: return &x; }
L1: { L2: p = leak();  L3: y = *p; }
```
-/

def leakProg : Program where
  funs := [("leak",
    { params := [], locals := [("x", 5)], body := .ret 10 (some (.addr "x")) })]
  globals := fun x => if x = "p" then some 0 else if x = "y" then some 1 else none

def leakStmt : Stmt :=
  .seq 1 (.call 2 (some "p") "leak" []) (.assign 3 (.var "y") (.deref (.var "p")))

/-- `leak` calls nothing; the labels 1, 2, 3 and 10 are distinct. -/
def leakSubj : Subject where
  prog := leakProg
  stmt := leakStmt
  wf := ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩

def leakState : State FunMem := topState [.int 0, .int 0]

/-- The dereference at `L3` faults: the local of `leak` is out of scope. -/
example : AlarmRaised leakSubj leakState 3 .invalidAccess :=
  alarm_of_run (n := 7) (by decide)

/-- When the fault is raised, `p` still points to the released block 2: going
out of scope rewrites no other block. -/
example : load (run leakProg 7 (Config.entry leakStmt leakState)).2.mem 0 = some (.ptr 2) ∧
    load (run leakProg 7 (Config.entry leakStmt leakState)).2.mem 2 = none := by decide

/-! ## A call that does not return

Globals `g`, `h` in blocks 0, 1, with `g = 3` and `h = 9`. The function `spin`
loops forever.

```
void spin(void) {
  int n = 0;
  L10: while (1) { L11: { L12: assert (g == 4); L13: n = n + 1; } }
}
L1: { L2: spin();  L3: g = 0; }
```
-/

def spinAssert : Stmt := .assert 12 (.binop .eq (.var "g") (.const 4))

def spinIncr : Stmt := .assign 13 (.var "n") (.binop .add (.var "n") (.const 1))

def spinBody : Stmt := .seq 11 spinAssert spinIncr

def spinDef : FunDef where
  params := []
  locals := [("n", 0)]
  body := .loop 10 (.const 1) spinBody

def spinProg : Program where
  funs := [("spin", spinDef)]
  globals := fun x => if x = "g" then some 0 else if x = "h" then some 1 else none

def spinStmt : Stmt := .seq 1 (.call 2 none "spin" []) (.assign 3 (.var "g") (.const 0))

/-- `spin` calls nothing; the labels 1, 2, 3 and 10 to 13 are distinct. -/
def spinSubj : Subject where
  prog := spinProg
  stmt := spinStmt
  wf := ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩

def spinState : State FunMem := topState [.int 3, .int 9]

/-- Reach: `L13`, inside the call, is visited. -/
example : Reach spinSubj spinState 13 := by
  obtain ⟨env, hv⟩ :=
    visit_of_run (n := 6) (t := spinSubj) (σ := spinState) (l := 13) (by decide)
  exact ⟨env, _, hv⟩

/-- Safety: the assertion `L12`, inside the call, fails at a visit. -/
example : AssertionFails spinSubj spinState 12 :=
  assertionFails_of_run (n := 4) (by decide)

/-! ### The frame lemma inside the call

`h` is in the frame of the statement: no finite prefix reads or writes block
1. The proof follows every configuration of the execution, which cycles through
the loop of `spin` forever; `SpinConf` lists them. -/

/-- `InFrame` holds when an invariant of the configurations ensures that no
step reads or writes the block. -/
theorem inFrame_of_invariant {M : Type} [Memory M] {t : Subject} {σ : State M}
    {b : Block} (P : Config M → Prop) (h₀ : P (Config.entry t.stmt σ))
    (hstep : ∀ c evs c', P c → step t.prog c = some (evs, c') →
      P c' ∧ ∀ e ∈ evs, ¬ e.Accesses b) :
    InFrame t σ b := by
  intro evs c hpre
  suffices H : ∀ c₁ evs c₂, Steps t.prog c₁ evs c₂ → P c₁ →
      ∀ e ∈ evs, ¬ e.Accesses b from
    H _ _ _ hpre h₀
  intro c₁ evs c₂ hs
  induction hs with
  | refl => intro _ e he; simp at he
  | head hst _ ih =>
    intro hP e he
    obtain ⟨hP', hev⟩ := hstep _ _ _ hP hst
    rcases List.mem_append.mp he with he | he
    · exact hev e he
    · exact ih hP' e he

/-- The call frame of `spin`. -/
def spinK : Cont := .call 2 none spinState.env [2] (.seq (.assign 3 (.var "g") (.const 0)) .stop)

/-- The continuation inside the loop of `spin`. -/
def spinL : Cont := .loop 10 (.const 1) spinBody spinK

/-- The environment of `spin`: its local `n` is block 2. -/
def spinEnv : Env := Env.bind ["n"] [2]

/-- The configurations of the execution of `spinStmt` from `spinState`. -/
inductive SpinConf : Config FunMem → Prop
  | entry : SpinConf (Config.entry spinStmt spinState)
  | call : SpinConf (.run (.call 2 none "spin" [])
      (.seq (.assign 3 (.var "g") (.const 0)) .stop) spinState.env spinState.mem)
  | loop (m : FunMem) : SpinConf (.run spinDef.body spinK spinEnv m)
  | body (m : FunMem) : SpinConf (.run spinBody spinL spinEnv m)
  | assert (m : FunMem) : SpinConf (.run spinAssert (.seq spinIncr spinL) spinEnv m)
  | afterAssert (m : FunMem) : SpinConf (.next (.seq spinIncr spinL) spinEnv m)
  | incr (m : FunMem) : SpinConf (.run spinIncr spinL spinEnv m)
  | afterIncr (m : FunMem) : SpinConf (.next spinL spinEnv m)
  | fault (l : Label) (a : Alarm) (m : FunMem) : SpinConf (.fault l a m)

theorem spin_resolve_g : resolve spinProg spinEnv "g" = some 0 := rfl

theorem spin_resolve_n : resolve spinProg spinEnv "n" = some 2 := rfl

/-- The assertion reads `g` only. -/
theorem spin_assert_events (m : FunMem) :
    (evalExpr spinProg spinEnv m (.binop .eq (.var "g") (.const 4))).1 = [.read 0] := by
  cases h : loadValue m 0 <;> simp [evalExpr, spin_resolve_g, h]

/-- The increment reads and writes `n` only. -/
theorem spin_incr_events (m : FunMem) :
    ∀ e ∈ (execAssign spinProg spinEnv m (.var "n")
      (.binop .add (.var "n") (.const 1))).1, e = .read 2 ∨ e = .write 2 := by
  cases h : loadValue m 2 with
  | error a => simp [execAssign, evalExpr, spin_resolve_n, h]
  | ok v =>
    cases v with
    | ptr | escaped => simp [execAssign, evalExpr, spin_resolve_n, h, BinOp.eval]
    | int n =>
      cases hs : store m 2 (.int (n + 1)) <;>
        simp [execAssign, evalExpr, evalLExpr, spin_resolve_n, h, BinOp.eval, hs]

theorem spin_step {c c' : Config FunMem} {evs : List Event} (hc : SpinConf c)
    (hs : step spinProg c = some (evs, c')) :
    SpinConf c' ∧ ∀ e ∈ evs, ¬ e.Accesses 1 := by
  cases hc with
  | entry =>
    have h : step spinProg (Config.entry spinStmt spinState) =
        some ([], .run (.call 2 none "spin" [])
          (.seq (.assign 3 (.var "g") (.const 0)) .stop) spinState.env spinState.mem) := rfl
    rw [h] at hs; cases hs
    exact ⟨.call, by simp⟩
  | call =>
    have h : step spinProg (.run (.call 2 none "spin" [])
          (.seq (.assign 3 (.var "g") (.const 0)) .stop) spinState.env spinState.mem) =
        some ([.scopeEnter 2],
          .run spinDef.body spinK spinEnv (createAll spinState.mem [.int 0]).2) := rfl
    rw [h] at hs; cases hs
    exact ⟨.loop _, by simp [Event.Accesses]⟩
  | loop m =>
    have h : step spinProg (.run spinDef.body spinK spinEnv m) =
        some ([], .run spinBody spinL spinEnv m) := rfl
    rw [h] at hs; cases hs
    exact ⟨.body m, by simp⟩
  | body m =>
    have h : step spinProg (.run spinBody spinL spinEnv m) =
        some ([], .run spinAssert (.seq spinIncr spinL) spinEnv m) := rfl
    rw [h] at hs; cases hs
    exact ⟨.assert m, by simp⟩
  | assert m =>
    have h : step spinProg (.run spinAssert (.seq spinIncr spinL) spinEnv m) =
        some ((evalExpr spinProg spinEnv m (.binop .eq (.var "g") (.const 4))).1,
          .next (.seq spinIncr spinL) spinEnv m) := rfl
    rw [h] at hs; cases hs
    refine ⟨.afterAssert m, ?_⟩
    rw [spin_assert_events m]
    simp [Event.Accesses]
  | afterAssert m =>
    have h : step spinProg (.next (.seq spinIncr spinL) spinEnv m) =
        some ([], .run spinIncr spinL spinEnv m) := rfl
    rw [h] at hs; cases hs
    exact ⟨.incr m, by simp⟩
  | incr m =>
    simp only [step, spinIncr, stepStmt, Option.some.injEq] at hs
    have hev := spin_incr_events m
    split at hs
    · next evs' m' hexec =>
      cases hs
      rw [hexec] at hev
      refine ⟨.afterIncr m', fun e he => ?_⟩
      rcases hev e he with rfl | rfl <;> simp [Event.Accesses]
    · next evs' a hexec =>
      cases hs
      rw [hexec] at hev
      refine ⟨.fault _ _ _, fun e he => ?_⟩
      rcases hev e he with rfl | rfl <;> simp [Event.Accesses]
  | afterIncr m =>
    have h : step spinProg (.next spinL spinEnv m) =
        some ([], .run spinDef.body spinK spinEnv m) := rfl
    rw [h] at hs; cases hs
    exact ⟨.loop m, by simp⟩
  | fault l a m => simp [step] at hs

/-- `h` is in the frame of `spinStmt` from `spinState`. -/
theorem spin_inFrame : InFrame spinSubj spinState 1 :=
  inFrame_of_invariant SpinConf .entry fun _ _ _ hc hs => spin_step hc hs

/-- The frame lemma, applied: at every visit, the visits inside `spin`
included, `h` holds 9, its value at entry. -/
theorem spin_frame {l : Label} {env : Env} {m : FunMem}
    (hv : Visit spinSubj spinState l env m) : load m 1 = some (.int 9) := by
  obtain ⟨evs, st, k, hpre, _⟩ := hv
  have hlive : Live spinState.mem 1 := rfl
  have hload : load spinState.mem 1 = some (.int 9) := rfl
  exact frame_no_sweep_rewrite hlive.issued (by simp [hload]) hpre fun e he hw =>
    spin_inFrame evs _ hpre e he (Event.accesses_of_writes hw)

#check_axioms Checks.spin_frame

/-! ## The body of a function as the subject

The body of `spin` is a statement of `spinProg`, so it forms a subject with
that program. It starts in the environment of `spin`, whose local `n` is block
2, with `g = 3`, `h = 9` and `n = 0`. -/

/-- The labels 10 to 13 are labels of the program; the body is a statement of
it. -/
def spinBodySubj : Subject where
  prog := spinProg
  stmt := spinDef.body
  wf := ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩

def spinBodyState : State FunMem := ⟨spinEnv, memOf [.int 3, .int 9, .int 0]⟩

/-- Safety: the assertion `L12` fails at a visit. -/
example : AssertionFails spinBodySubj spinBodyState 12 :=
  assertionFails_of_run (n := 2) (by decide)

/-- Reach: `L13` is visited, with `n` still `0`. -/
example : ∃ env m, Visit spinBodySubj spinBodyState 13 env m ∧
    load m 2 = some (.int 0) := by
  obtain ⟨env, hv⟩ := visit_of_run (n := 4) (t := spinBodySubj)
    (σ := spinBodyState) (l := 13) (by decide)
  exact ⟨env, _, hv, by decide⟩

/-! ## Comparison with the null pointer

The integer `0` is the null pointer. A pointer to a block compares unequal to
it, in both operand orders; null compares equal to null. Comparing a pointer
with a nonzero integer stays ill-formed. -/

example : BinOp.eval .eq (.ptr 3) (.int 0) = .ok (.int 0) := rfl
example : BinOp.eval .eq (.int 0) (.ptr 3) = .ok (.int 0) := rfl
example : BinOp.eval .eq (.int 0) (.int 0) = .ok (.int 1) := rfl
example : BinOp.eval .eq (.ptr 3) (.int 5) = .error .illFormed := rfl
example : BinOp.eval .eq (.int 5) (.ptr 3) = .error .illFormed := rfl

/-- In the aliasing program, `p` points to `g`: `p == 0` and `0 == p` evaluate
to `0` and read `p` only. -/
example : evalExpr aliasProg aliasState.env aliasState.mem
    (.binop .eq (.var "p") (.const 0)) = ([.read 1], .ok (.int 0)) := rfl
example : evalExpr aliasProg aliasState.env aliasState.mem
    (.binop .eq (.const 0) (.var "p")) = ([.read 1], .ok (.int 0)) := rfl

end Checks
