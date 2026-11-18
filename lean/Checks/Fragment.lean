import ReuseModel

/-!
# The fragment conditions

`WellFormed p s` is decided by `decide` for concrete programs, once a rank on
functions is given for `NonRecursive`. This file shows statements that meet
the conditions:

* a call chain, observed from a statement outside the function bodies;
* the body of a function of the program;
* a statement inside the body of a function of the program.

It also shows programs and statements that do not, each failing one condition
only:

* duplicate labels in the observed statement: the label `8` names two
  statements;
* a statement outside the function bodies that reuses one of their labels;
* duplicate labels across two function bodies, for every observed statement;
* direct recursion: `f` calls `f`;
* mutual recursion: `f` calls `g`, which calls `f`.

For each rejected program and statement, no `Subject` has them, so the
observations and the frame lemma do not apply to them.
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
  ⟨by decide, ⟨fun f => if f = "f" then 1 else 0, by decide⟩, by decide,
    by decide⟩

/-! ## A function body and a statement inside it

```
void g(void) { L21: skip; }
void f(void) { L20: { L22: g(); L23: assert (1); } }
```

The body of `f` and the call `L22` inside it are statements of the program.
Their labels are labels of the program, and they meet the conditions by the
first case of `stmtLabels`.
-/

def nestBody : Stmt := .seq 20 (.call 22 none "g" []) (.assert 23 (.const 1))

def nestCall : Stmt := .call 22 none "g" []

def nestProg : Program where
  funs := [("f", { params := [], locals := [], body := nestBody }),
           ("g", { params := [], locals := [], body := .skip 21 })]
  globals := fun _ => none

example : nestBody.labels.all (· ∈ nestProg.labels) := by decide

/-- The subject whose statement is the body of `f`. -/
def nestBodySubj : Subject where
  prog := nestProg
  stmt := nestBody
  wf := ⟨by decide, ⟨fun f => if f = "f" then 1 else 0, by decide⟩, by decide,
    by decide⟩

/-- The subject whose statement is the call `L22`, inside the body of `f`. -/
def nestCallSubj : Subject where
  prog := nestProg
  stmt := nestCall
  wf := ⟨by decide, ⟨fun f => if f = "f" then 1 else 0, by decide⟩, by decide,
    by decide⟩

/-- The same conditions, from the lemmas: the body of `f`, which a call to `f`
reaches, and the call `L22` inside it. -/
example : WellFormed nestProg nestCall :=
  (nestBodySubj.wf.body (f := "f") rfl).sub (by decide)

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

example : dupProg.labels.Nodup := by decide

/-- `dupStmt` is not a statement of a function body, and its labels are not
pairwise distinct. -/
theorem dup_not_wellFormed : ¬ WellFormed dupProg dupStmt :=
  fun h => absurd h.stmtLabels (by decide)

theorem dup_no_subject (t : Subject) : ¬ (t.prog = dupProg ∧ t.stmt = dupStmt) :=
  fun ⟨hp, hs⟩ => dup_not_wellFormed (hp ▸ hs ▸ t.wf)

/-! ## A label of a function body reused outside

The statement is not a statement of the program, and its label `22` is the
label of the call in the body of `f`.

```
L22: assert (0);
```
-/

def clashStmt : Stmt := .assert 22 (.const 0)

example : nestProg.NamesUnique := by decide

example : nestProg.NonRecursive :=
  ⟨fun f => if f = "f" then 1 else 0, by decide⟩

example : nestProg.labels.Nodup := by decide

theorem clash_not_wellFormed : ¬ WellFormed nestProg clashStmt :=
  fun h => absurd h.stmtLabels (by decide)

theorem clash_no_subject (t : Subject) :
    ¬ (t.prog = nestProg ∧ t.stmt = clashStmt) :=
  fun ⟨hp, hs⟩ => clash_not_wellFormed (hp ▸ hs ▸ t.wf)

/-! ## Duplicate labels across two function bodies

```
void f(void) { L20: skip; }
void g(void) { L20: assert (0); }
```

No statement is in the fragment with this program, the bodies of `f` and `g`
included.
-/

def repProg : Program where
  funs := [("f", { params := [], locals := [], body := .skip 20 }),
           ("g", { params := [], locals := [], body := .assert 20 (.const 0) })]
  globals := fun _ => none

example : repProg.NamesUnique := by decide

example : repProg.NonRecursive := ⟨fun _ => 0, by decide⟩

/-- The body of `f` is a statement of the program. -/
example : Stmt.skip 20 ∈ repProg.stmts := by decide

theorem rep_not_wellFormed (s : Stmt) : ¬ WellFormed repProg s :=
  fun h => absurd h.labelsUnique (by decide)

theorem rep_no_subject (t : Subject) : t.prog ≠ repProg :=
  fun hp => rep_not_wellFormed t.stmt (hp ▸ t.wf)

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

example : recProg.labels.Nodup := by decide

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

/-- The body of `f` is not in the fragment either. -/
example : ¬ WellFormed recProg recFun.body :=
  fun h => rec_not_nonRecursive h.nonRecursive

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

example : mutProg.labels.Nodup := by decide

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

/-- The bodies of `f` and `g` are not in the fragment either. -/
example : ¬ WellFormed mutProg mutF.body ∧ ¬ WellFormed mutProg mutG.body :=
  ⟨fun h => mut_not_nonRecursive h.nonRecursive,
    fun h => mut_not_nonRecursive h.nonRecursive⟩

end Checks
