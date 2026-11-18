import ReuseModel.Semantics

/-!
# Observations

What an analysis claims about the executions of the statement of a subject
`t` from a state `σ`:

* Exit, on normal ends: the outcome and the memory;
* Reach, on every finite prefix: the statements visited;
* Safety, on every finite prefix: the run-time alarms raised and the labelled
  assertions that fail at a visit.

Reach and Safety are defined on finite prefixes. They therefore include the
visits before a fault and the visits inside a call that does not return.

Each observation takes a `Subject`, so it is only defined for programs of the
fragment (`WellFormed`). Labels are pairwise distinct there, so a label passed
to Reach or Safety names at most one statement of the observed statement and
of the function bodies.
-/

namespace ReuseModel

section
variable {M : Type} [Memory M]

/-- Exit: the execution of the statement of `t` from `σ` ends normally with
outcome `o` and memory `m`. -/
def Exit (t : Subject) (σ : State M) (o : Outcome) (m : M) : Prop :=
  ∃ evs, Prefix t σ evs (.done o m)

/-- A visit to the statement labelled `l` during the execution of the
statement of `t` from `σ`: a configuration of a finite prefix in which that
statement is about to execute, with local environment `env` and memory `m`. -/
def Visit (t : Subject) (σ : State M) (l : Label) (env : Env) (m : M) : Prop :=
  ∃ evs st k, Prefix t σ evs (.run st k env m) ∧ st.label = l

/-- Reach: the statement labelled `l` is visited on some finite prefix. -/
def Reach (t : Subject) (σ : State M) (l : Label) : Prop :=
  ∃ env m, Visit t σ l env m

/-- Whether an assertion holds: its expression evaluates without alarm to a
true value. -/
def assertionHolds (p : Program) (env : Env) (m : M) (e : Expr) : Bool :=
  match (evalExpr p env m e).2 with
  | .ok v => v.truth
  | .error _ => false

/-- Safety, run-time alarms: some finite prefix ends with the alarm `a` raised
by the statement labelled `l`. -/
def AlarmRaised (t : Subject) (σ : State M) (l : Label) (a : Alarm) : Prop :=
  ∃ evs m, Prefix t σ evs (.fault l a m)

/-- Safety, labelled assertions: the assertion labelled `l` does not hold at
some visit. -/
def AssertionFails (t : Subject) (σ : State M) (l : Label) : Prop :=
  ∃ evs e k env m, Prefix t σ evs (.run (.assert l e) k env m) ∧
    assertionHolds t.prog env m e = false

end

/-- A Safety violation: a run-time alarm or a failed labelled assertion. -/
inductive Violation where
  | alarm (l : Label) (a : Alarm)
  | assertion (l : Label)
  deriving DecidableEq, Repr

/-- Safety: the violations that occur on some finite prefix. -/
def Unsafe {M : Type} [Memory M] (t : Subject) (σ : State M) : Violation → Prop
  | .alarm l a => AlarmRaised t σ l a
  | .assertion l => AssertionFails t σ l

end ReuseModel
