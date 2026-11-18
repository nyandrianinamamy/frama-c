import ReuseModel

/-!
# The fragment conditions

`WellFormed p s` is decided by `decide` for concrete programs, once a rank on
functions is given for `NonRecursive`. This file shows one program that meets
the conditions with a call chain, and three that do not, each failing one
condition only:

* duplicate labels: the label `8` names two statements;
* direct recursion: `f` calls `f`;
* mutual recursion: `f` calls `g`, which calls `f`.

For each rejected program, no `Subject` has that program and statement, so the
observations and the frame lemma do not apply to it.
-/

namespace Checks

open ReuseModel

/-! ## A call chain

```
void g(void) { L21: skip; }
void f(void) { L20: g(); }
L1: f();
```
-/

def chainProg : Program where
  funs := [("f", { params := [], locals := [], body := .call 20 none "g" [] }),
           ("g", { params := [], locals := [], body := .skip 21 })]
  globals := fun _ => none

def chainStmt : Stmt := .call 1 none "f" []

/-- The rank `f ↦ 1, g ↦ 0` decreases along the call from `f` to `g`. -/
theorem chain_wellFormed : WellFormed chainProg chainStmt :=
  ⟨by decide, ⟨fun f => if f = "f" then 1 else 0, by decide⟩, by decide⟩

/-! ## Duplicate labels

The label `8` names two statements. Without the condition, Reach at `8` would
hold through `skip`, although the assertion labelled `8` is never visited.

```
L7: if (1) L8: skip; else L8: assert (0);
```
-/

def dupProg : Program where
  funs := []
  globals := fun _ => none

def dupStmt : Stmt := .ite 7 (.const 1) (.skip 8) (.assert 8 (.const 0))

example : dupProg.NamesUnique := by decide

example : dupProg.NonRecursive := ⟨fun _ => 0, by decide⟩

example : dupStmt.labels = [7, 8, 8] := rfl

theorem dup_not_wellFormed : ¬ WellFormed dupProg dupStmt :=
  fun h => absurd h.labelsUnique (by decide)

theorem dup_no_subject (t : Subject) : ¬ (t.prog = dupProg ∧ t.stmt = dupStmt) :=
  fun ⟨hp, hs⟩ => dup_not_wellFormed (hp ▸ hs ▸ t.wf)

/-! ## Direct recursion

```
void f(void) { L20: f(); }
L1: f();
```
-/

def recFun : FunDef where
  params := []
  locals := []
  body := .call 20 none "f" []

def recProg : Program where
  funs := [("f", recFun)]
  globals := fun _ => none

def recStmt : Stmt := .call 1 none "f" []

example : recProg.NamesUnique := by decide

example : (recStmt.labels ++ recProg.labels).Nodup := by decide

/-- A rank would have to satisfy `rank f < rank f`. -/
theorem rec_not_nonRecursive : ¬ recProg.NonRecursive := by
  rintro ⟨rank, h⟩
  have := h ("f", recFun) (by simp [recProg]) "f" (by simp [recFun, Stmt.callees])
  exact Nat.lt_irrefl _ this

theorem rec_not_wellFormed : ¬ WellFormed recProg recStmt :=
  fun h => rec_not_nonRecursive h.nonRecursive

theorem rec_no_subject (t : Subject) : ¬ (t.prog = recProg ∧ t.stmt = recStmt) :=
  fun ⟨hp, hs⟩ => rec_not_wellFormed (hp ▸ hs ▸ t.wf)

/-! ## Mutual recursion

```
void f(void) { L20: g(); }
void g(void) { L21: f(); }
L1: f();
```
-/

def mutF : FunDef where
  params := []
  locals := []
  body := .call 20 none "g" []

def mutG : FunDef where
  params := []
  locals := []
  body := .call 21 none "f" []

def mutProg : Program where
  funs := [("f", mutF), ("g", mutG)]
  globals := fun _ => none

def mutStmt : Stmt := .call 1 none "f" []

example : mutProg.NamesUnique := by decide

example : (mutStmt.labels ++ mutProg.labels).Nodup := by decide

/-- A rank would have to satisfy `rank g < rank f` and `rank f < rank g`. -/
theorem mut_not_nonRecursive : ¬ mutProg.NonRecursive := by
  rintro ⟨rank, h⟩
  have h₁ := h ("f", mutF) (by simp [mutProg]) "g" (by simp [mutF, Stmt.callees])
  have h₂ := h ("g", mutG) (by simp [mutProg]) "f" (by simp [mutG, Stmt.callees])
  exact Nat.lt_asymm h₁ h₂

theorem mut_not_wellFormed : ¬ WellFormed mutProg mutStmt :=
  fun h => mut_not_nonRecursive h.nonRecursive

theorem mut_no_subject (t : Subject) : ¬ (t.prog = mutProg ∧ t.stmt = mutStmt) :=
  fun ⟨hp, hs⟩ => mut_not_wellFormed (hp ▸ hs ▸ t.wf)

end Checks
