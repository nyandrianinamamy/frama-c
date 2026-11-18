import ReuseModel.Memory

/-!
# Concrete semantics

A small-step semantics with an explicit continuation, which holds the call
stack. Each step reports the events it performs: reads and writes of blocks,
and the start and end of the lifetime of a block. A read or a write is reported
when the block is designated, also when the access then faults.

The step function is deterministic. A configuration is final when the
statement has ended (`done`) or a run-time alarm stopped it (`fault`); any
other configuration has exactly one step.

An execution is the sequence of configurations obtained by iterating the step
function (`run`). A finite prefix is a finite sequence of steps (`Steps`).
`steps_iff_run` shows that the finite prefixes from a configuration are exactly
the iterates of its execution. Observations are defined on finite prefixes, so
that they cover the configurations before a fault and inside a call that does
not return.
-/

namespace ReuseModel

open Memory

/-- Run-time alarms. -/
inductive Alarm where
  /-- Load or store on a block that is not live, or through an integer. -/
  | invalidAccess
  /-- Division by zero. -/
  | divByZero
  /-- The program leaves the fragment: an unbound variable or function, a
  wrong number of arguments, an operator applied to a pointer, or a caller
  that uses the value of a call that returned none. -/
  | illFormed
  deriving DecidableEq, Repr

/-- Events performed by a step. -/
inductive Event where
  | read (b : Block)
  | write (b : Block)
  /-- The block is created as a local of a call. -/
  | scopeEnter (b : Block)
  /-- The block, a local of a call, goes out of scope at its return. -/
  | scopeExit (b : Block)
  deriving DecidableEq, Repr

/-- The event reads or writes the block. Scope entry and exit are not
accesses. -/
def Event.Accesses : Event → Block → Prop
  | .read b, b' => b = b'
  | .write b, b' => b = b'
  | _, _ => False

/-- The event writes the block. -/
def Event.Writes : Event → Block → Prop
  | .write b, b' => b = b'
  | _, _ => False

theorem Event.accesses_of_writes {e : Event} {b : Block} (h : e.Writes b) :
    e.Accesses b := by
  cases e <;> simp_all [Event.Writes, Event.Accesses]

/-- A local environment: the blocks of the locals of the running function. -/
abbrev Env := Var → Option Block

/-- Bind variables to blocks, pairwise. -/
def Env.bind (xs : List Var) (bs : List Block) : Env :=
  fun x => (xs.zip bs).lookup x

/-- The block of a variable: a local of the running function, or else a
global. -/
def resolve (p : Program) (env : Env) (x : Var) : Option Block :=
  match env x with
  | some b => some b
  | none => p.globals x

section
variable {M : Type} [Memory M]

/-- Load the value of a block; a block that is not live faults. -/
def loadValue (m : M) (b : Block) : Except Alarm Value :=
  match load m b with
  | some v => .ok v
  | none => .error .invalidAccess

/-- Truth of a condition: a nonzero integer or a pointer. -/
def Value.truth : Value → Bool
  | .int n => n != 0
  | .ptr _ => true

/-- Binary operators. Division truncates toward zero, as in C. -/
def BinOp.eval : BinOp → Value → Value → Except Alarm Value
  | .add, .int a, .int b => .ok (.int (a + b))
  | .sub, .int a, .int b => .ok (.int (a - b))
  | .mul, .int a, .int b => .ok (.int (a * b))
  | .div, .int a, .int b => if b = 0 then .error .divByZero else .ok (.int (a.tdiv b))
  | .eq, .int a, .int b => .ok (.int (if a = b then 1 else 0))
  | .eq, .ptr a, .ptr b => .ok (.int (if a = b then 1 else 0))
  | .lt, .int a, .int b => .ok (.int (if a < b then 1 else 0))
  | _, _, _ => .error .illFormed

/-- Evaluate an expression: the reads it performs and its value or alarm. -/
def evalExpr (p : Program) (env : Env) (m : M) : Expr → List Event × Except Alarm Value
  | .const n => ([], .ok (.int n))
  | .var x =>
    match resolve p env x with
    | some b => ([.read b], loadValue m b)
    | none => ([], .error .illFormed)
  | .addr x =>
    match resolve p env x with
    | some b => ([], .ok (.ptr b))
    | none => ([], .error .illFormed)
  | .deref e =>
    match evalExpr p env m e with
    | (evs, .ok (.ptr b)) => (evs ++ [.read b], loadValue m b)
    | (evs, .ok (.int _)) => (evs, .error .invalidAccess)
    | (evs, .error a) => (evs, .error a)
  | .binop op e₁ e₂ =>
    match evalExpr p env m e₁ with
    | (evs₁, .error a) => (evs₁, .error a)
    | (evs₁, .ok v₁) =>
      match evalExpr p env m e₂ with
      | (evs₂, .error a) => (evs₁ ++ evs₂, .error a)
      | (evs₂, .ok v₂) => (evs₁ ++ evs₂, op.eval v₁ v₂)

/-- Evaluate the block designated by a left-hand side. -/
def evalLExpr (p : Program) (env : Env) (m : M) : LExpr → List Event × Except Alarm Block
  | .var x =>
    match resolve p env x with
    | some b => ([], .ok b)
    | none => ([], .error .illFormed)
  | .deref e =>
    match evalExpr p env m e with
    | (evs, .ok (.ptr b)) => (evs, .ok b)
    | (evs, .ok (.int _)) => (evs, .error .invalidAccess)
    | (evs, .error a) => (evs, .error a)

/-- Evaluate arguments from left to right. -/
def evalArgs (p : Program) (env : Env) (m : M) :
    List Expr → List Event × Except Alarm (List Value)
  | [] => ([], .ok [])
  | e :: es =>
    match evalExpr p env m e with
    | (evs, .error a) => (evs, .error a)
    | (evs, .ok v) =>
      match evalArgs p env m es with
      | (evs', .error a) => (evs ++ evs', .error a)
      | (evs', .ok vs) => (evs ++ evs', .ok (v :: vs))

/-- An assignment: evaluate the value, then the target block, then store. -/
def execAssign (p : Program) (env : Env) (m : M) (lv : LExpr) (e : Expr) :
    List Event × Except Alarm M :=
  match evalExpr p env m e with
  | (evs₁, .error a) => (evs₁, .error a)
  | (evs₁, .ok v) =>
    match evalLExpr p env m lv with
    | (evs₂, .error a) => (evs₁ ++ evs₂, .error a)
    | (evs₂, .ok b) =>
      match store m b v with
      | some m' => (evs₁ ++ evs₂ ++ [.write b], .ok m')
      | none => (evs₁ ++ evs₂ ++ [.write b], .error .invalidAccess)

/-- What a call needs to start the callee. -/
structure CallEntry (M : Type) where
  /-- The body of the callee. -/
  body : Stmt
  /-- The block of the caller that receives the returned value. -/
  dst : Option Block
  /-- The blocks created for the parameters and locals of the callee. -/
  locals : List Block
  /-- The local environment of the callee. -/
  env : Env
  /-- The memory after the creation of the locals. -/
  mem : M

/-- Resolve the variable that receives the result of a call. -/
def resolveDst (p : Program) (env : Env) : Option Var → Except Alarm (Option Block)
  | none => .ok none
  | some x =>
    match resolve p env x with
    | some b => .ok (some b)
    | none => .error .illFormed

/-- A call: evaluate the arguments, then create one block per parameter and
per local of the callee. -/
def execCall (p : Program) (env : Env) (m : M) (dst : Option Var) (f : FunName)
    (args : List Expr) : List Event × Except Alarm (CallEntry M) :=
  match evalArgs p env m args with
  | (evs, .error a) => (evs, .error a)
  | (evs, .ok vs) =>
    match resolveDst p env dst, p.funs f with
    | .ok d, some fd =>
      if vs.length = fd.params.length then
        let r := createAll m (vs ++ fd.locals.map fun x => Value.int x.2)
        (evs ++ r.1.map Event.scopeEnter,
          .ok { body := fd.body
                dst := d
                locals := r.1
                env := Env.bind (fd.params ++ fd.locals.map Prod.fst) r.1
                mem := r.2 })
      else (evs, .error .illFormed)
    | _, _ => (evs, .error .illFormed)

end

/-- Continuations: what remains to execute after the current statement. -/
inductive Cont where
  /-- The end of the statement under execution. -/
  | stop
  /-- Then execute `s`. -/
  | seq (s : Stmt) (k : Cont)
  /-- Then test the loop `while (c) body` labelled `l` again. -/
  | loop (l : Label) (c : Expr) (body : Stmt) (k : Cont)
  /-- Then return to the caller: release the callee's locals, store the
  returned value into `dst`, and continue in the caller's environment. `site`
  is the label of the call. -/
  | call (site : Label) (dst : Option Block) (env : Env) (locals : List Block) (k : Cont)

/-- How a statement ends normally. -/
inductive Outcome where
  /-- Its last instruction completed. -/
  | completed
  /-- It executed a `return`, with the returned value. -/
  | returned (v : Option Value)
  deriving DecidableEq, Repr

/-- Configurations. -/
inductive Config (M : Type) where
  /-- The statement `s` is about to execute: a visit to `s`. -/
  | run (s : Stmt) (k : Cont) (env : Env) (m : M)
  /-- A statement has completed; continue with `k`. -/
  | next (k : Cont) (env : Env) (m : M)
  /-- A `return` with value `v` unwinds `k` to the nearest call. -/
  | ret (v : Option Value) (k : Cont) (m : M)
  /-- The statement under execution has ended normally. -/
  | done (o : Outcome) (m : M)
  /-- The alarm `a`, raised by the statement labelled `l`, stopped the
  execution. -/
  | fault (l : Label) (a : Alarm) (m : M)

section
variable {M : Type} [Memory M]

/-- The memory of a configuration. -/
def Config.mem : Config M → M
  | .run _ _ _ m => m
  | .next _ _ m => m
  | .ret _ _ m => m
  | .done _ m => m
  | .fault _ _ m => m

/-- The continuation of a configuration; `stop` for a final one. -/
def Config.cont : Config M → Cont
  | .run _ k _ _ => k
  | .next k _ _ => k
  | .ret _ k _ => k
  | .done _ _ => .stop
  | .fault _ _ _ => .stop

/-- One step from a statement. -/
def stepStmt (p : Program) : Stmt → Cont → Env → M → List Event × Config M
  | .skip _, k, env, m => ([], .next k env m)
  | .assign l lv e, k, env, m =>
    match execAssign p env m lv e with
    | (evs, .ok m') => (evs, .next k env m')
    | (evs, .error a) => (evs, .fault l a m)
  | .seq _ s₁ s₂, k, env, m => ([], .run s₁ (.seq s₂ k) env m)
  | .ite l c s₁ s₂, k, env, m =>
    match evalExpr p env m c with
    | (evs, .ok v) => (evs, .run (if v.truth then s₁ else s₂) k env m)
    | (evs, .error a) => (evs, .fault l a m)
  | .loop l c body, k, env, m =>
    match evalExpr p env m c with
    | (evs, .ok v) =>
      if v.truth then (evs, .run body (.loop l c body k) env m)
      else (evs, .next k env m)
    | (evs, .error a) => (evs, .fault l a m)
  | .call l dst f args, k, env, m =>
    match execCall p env m dst f args with
    | (evs, .ok ce) => (evs, .run ce.body (.call l ce.dst env ce.locals k) ce.env ce.mem)
    | (evs, .error a) => (evs, .fault l a m)
  | .ret _ none, k, _, m => ([], .ret none k m)
  | .ret l (some e), k, env, m =>
    match evalExpr p env m e with
    | (evs, .ok v) => (evs, .ret (some v) k m)
    | (evs, .error a) => (evs, .fault l a m)
  | .assert _ e, k, env, m => ((evalExpr p env m e).1, .next k env m)

/-- One step after a statement has completed. Reaching the end of a function
body returns no value. -/
def stepNext : Cont → Env → M → Config M
  | .stop, _, m => .done .completed m
  | .seq s k, env, m => .run s k env m
  | .loop l c body k, env, m => .run (.loop l c body) k env m
  | k@(.call ..), _, m => .ret none k m

/-- One step of a `return`. At the nearest call, the callee's locals go out of
scope, then the returned value is stored into the caller's block. -/
def stepRet : Option Value → Cont → M → List Event × Config M
  | v, .stop, m => ([], .done (.returned v) m)
  | v, .seq _ k, m => ([], .ret v k m)
  | v, .loop _ _ _ k, m => ([], .ret v k m)
  | v, .call site dst env locals k, m =>
    let m₁ := releaseAll m locals
    let evs := locals.map Event.scopeExit
    match dst, v with
    | none, _ => (evs, .next k env m₁)
    | some _, none => (evs, .fault site .illFormed m₁)
    | some b, some v =>
      match store m₁ b v with
      | some m₂ => (evs ++ [.write b], .next k env m₂)
      | none => (evs ++ [.write b], .fault site .invalidAccess m₁)

/-- The step function; `none` on a final configuration. -/
def step (p : Program) : Config M → Option (List Event × Config M)
  | .run s k env m => some (stepStmt p s k env m)
  | .next k env m => some ([], stepNext k env m)
  | .ret v k m => some (stepRet v k m)
  | .done _ _ => none
  | .fault _ _ _ => none

/-- A finite prefix: a finite sequence of steps from `c` to `c'`, with the
events it performs. -/
inductive Steps (p : Program) : Config M → List Event → Config M → Prop
  | refl (c : Config M) : Steps p c [] c
  | head {c c' c'' : Config M} {evs evs' : List Event} :
      step p c = some (evs, c') → Steps p c' evs' c'' → Steps p c (evs ++ evs') c''

/-- The execution from `c`, observed after `n` steps: the events performed and
the configuration reached. A final configuration ends the iteration. -/
def run (p : Program) : Nat → Config M → List Event × Config M
  | 0, c => ([], c)
  | n + 1, c =>
    match step p c with
    | some (evs, c') =>
      let r := run p n c'
      (evs ++ r.1, r.2)
    | none => ([], c)

theorem run_steps (p : Program) (n : Nat) (c : Config M) :
    Steps p c (run p n c).1 (run p n c).2 := by
  induction n generalizing c with
  | zero => exact Steps.refl c
  | succ n ih =>
    simp only [run]
    split
    · next evs c' h => exact Steps.head h (ih c')
    · exact Steps.refl c

theorem steps_run {p : Program} {c c' : Config M} {evs : List Event}
    (h : Steps p c evs c') : ∃ n, run p n c = (evs, c') := by
  induction h with
  | refl c => exact ⟨0, rfl⟩
  | head hstep _ ih =>
    obtain ⟨n, hn⟩ := ih
    refine ⟨n + 1, ?_⟩
    simp [run, hstep, hn]

/-- The finite prefixes from `c` are the iterates of its execution. -/
theorem steps_iff_run {p : Program} {c c' : Config M} {evs : List Event} :
    Steps p c evs c' ↔ ∃ n, run p n c = (evs, c') := by
  constructor
  · exact steps_run
  · rintro ⟨n, hn⟩
    have h := run_steps p n c
    rw [hn] at h
    exact h

/-- The state in which a statement starts: the environment of the running
function and the memory. -/
structure State (M : Type) where
  env : Env
  mem : M

/-- The entry configuration of a statement. -/
def Config.entry (s : Stmt) (σ : State M) : Config M := .run s .stop σ.env σ.mem

/-- A finite prefix of the execution of `s` from `σ`. -/
def Prefix (p : Program) (s : Stmt) (σ : State M) (evs : List Event) (c : Config M) :
    Prop :=
  Steps p (Config.entry s σ) evs c

end

end ReuseModel
