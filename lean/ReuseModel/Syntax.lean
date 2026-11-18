/-!
# Syntax

The language of the model: whole-block loads and stores, sequencing,
conditionals, `while`, direct calls and return, and labelled assertions.

A value is an integer or a pointer to a whole block. There are no offsets into
a block, no arrays or structures, no pointer arithmetic and no casts between
pointers and integers.

The fragment of the model is given by `WellFormed`: each function is defined
once, no call is recursive, and the labels of the function bodies are pairwise
distinct. The observed statement is either a statement of a function body, or
a statement whose labels are pairwise distinct and distinct from those of the
function bodies. A `Subject` bundles a program, the observed statement and a
proof that they are in the fragment; the observations and the frame lemma are
stated for subjects.
-/

namespace ReuseModel

/-- A block: a unit of memory that holds one value. A block can stand for a
global, a local of a caller or an existing heap allocation; the model does not
distinguish them. -/
abbrev Block := Nat

/-- A value: an integer, or a pointer to a block. The integer `0` serves as
the null pointer: it compares unequal to every pointer to a block. -/
inductive Value where
  | int (n : Int)
  | ptr (b : Block)
  deriving DecidableEq, Repr

/-- A variable name. -/
abbrev Var := String

/-- A function name. -/
abbrev FunName := String

/-- A statement label. Every statement carries one, as every statement of
Frama-C has an identifier. Reach and Safety are observed by label. The fragment
requires the labels to be pairwise distinct (`WellFormed`), so that a label
names one statement of the program text and of the observed statement. -/
abbrev Label := Nat

/-- Binary operators. Comparisons return `1` or `0`. -/
inductive BinOp where
  | add
  | sub
  | mul
  | div
  | eq
  | lt
  deriving DecidableEq, Repr

/-- Expressions. Reading a variable or dereferencing a pointer loads a whole
block. -/
inductive Expr where
  /-- An integer constant. -/
  | const (n : Int)
  /-- The value of the block of a variable. -/
  | var (x : Var)
  /-- `&x`: a pointer to the block of a variable. -/
  | addr (x : Var)
  /-- `*e`: the value of the block that `e` points to. -/
  | deref (e : Expr)
  | binop (op : BinOp) (e₁ e₂ : Expr)
  deriving DecidableEq, Repr

/-- Left-hand sides of assignments. A store overwrites a whole block. -/
inductive LExpr where
  /-- The block of a variable. -/
  | var (x : Var)
  /-- `*e`: the block that `e` points to. -/
  | deref (e : Expr)
  deriving DecidableEq, Repr

/-- Statements. The first argument of each constructor is its label. -/
inductive Stmt where
  | skip (l : Label)
  /-- `lv = e;` -/
  | assign (l : Label) (lv : LExpr) (e : Expr)
  /-- `s₁ s₂` -/
  | seq (l : Label) (s₁ s₂ : Stmt)
  /-- `if (c) s₁ else s₂` -/
  | ite (l : Label) (c : Expr) (s₁ s₂ : Stmt)
  /-- `while (c) body` -/
  | loop (l : Label) (c : Expr) (body : Stmt)
  /-- `x = f(args);` or `f(args);`: a direct call. -/
  | call (l : Label) (dst : Option Var) (f : FunName) (args : List Expr)
  /-- `return e;` or `return;` -/
  | ret (l : Label) (e : Option Expr)
  /-- `/*@ assert e; */`: an assertion, named by its label. It has no effect
  on the execution; whether it holds at each visit is a Safety
  observation. -/
  | assert (l : Label) (e : Expr)
  deriving DecidableEq, Repr

/-- The label of a statement. -/
def Stmt.label : Stmt → Label
  | .skip l => l
  | .assign l _ _ => l
  | .seq l _ _ => l
  | .ite l _ _ _ => l
  | .loop l _ _ => l
  | .call l _ _ _ => l
  | .ret l _ => l
  | .assert l _ => l

/-- The labels of a statement and of the statements it contains, in
preorder. -/
def Stmt.labels : Stmt → List Label
  | .skip l => [l]
  | .assign l _ _ => [l]
  | .seq l s₁ s₂ => l :: (s₁.labels ++ s₂.labels)
  | .ite l _ s₁ s₂ => l :: (s₁.labels ++ s₂.labels)
  | .loop l _ body => l :: body.labels
  | .call l _ _ _ => [l]
  | .ret l _ => [l]
  | .assert l _ => [l]

/-- A statement and the statements it contains, in preorder. `Stmt.labels`
lists their labels in the same order. -/
def Stmt.subs : Stmt → List Stmt
  | s@(.seq _ s₁ s₂) => s :: (s₁.subs ++ s₂.subs)
  | s@(.ite _ _ s₁ s₂) => s :: (s₁.subs ++ s₂.subs)
  | s@(.loop _ _ body) => s :: body.subs
  | s => [s]

/-- The functions that a statement calls directly. -/
def Stmt.callees : Stmt → List FunName
  | .seq _ s₁ s₂ => s₁.callees ++ s₂.callees
  | .ite _ _ s₁ s₂ => s₁.callees ++ s₂.callees
  | .loop _ _ body => body.callees
  | .call _ _ f _ => [f]
  | _ => []

/-- A function definition. Each local is declared with an initial value, so
that reads of uninitialized locals are outside the model. -/
structure FunDef where
  params : List Var
  locals : List (Var × Int)
  body : Stmt

/-- A program: its function definitions, as a finite list of named
definitions, and the blocks of its global variables. A call looks up its callee
by name (`Program.lookup`). -/
structure Program where
  funs : List (FunName × FunDef)
  globals : Var → Option Block

/-- The definition of a function: the first entry of the list with that
name. -/
def Program.lookup (p : Program) (f : FunName) : Option FunDef :=
  p.funs.lookup f

/-- The labels of the bodies of the functions of the program. -/
def Program.labels (p : Program) : List Label :=
  p.funs.flatMap fun d => d.2.body.labels

/-- The statements of the bodies of the functions of the program: each body and
the statements it contains. -/
def Program.stmts (p : Program) : List Stmt :=
  p.funs.flatMap fun d => d.2.body.subs

/-- Each function of the program is defined once. -/
def Program.NamesUnique (p : Program) : Prop :=
  (p.funs.map Prod.fst).Nodup

instance (p : Program) : Decidable p.NamesUnique :=
  inferInstanceAs (Decidable (p.funs.map Prod.fst).Nodup)

/-- No call of the program is recursive: a rank on functions decreases along
every direct call. -/
def Program.NonRecursive (p : Program) : Prop :=
  ∃ rank : FunName → Nat,
    ∀ d ∈ p.funs, ∀ g ∈ d.2.body.callees, rank g < rank d.1

/-- The statement `s` of the program `p` is in the fragment of the model. The
language can express programs outside it; the observations and the frame lemma
are stated for subjects, which carry this proof.

* `namesUnique`: each function is defined once, so the entries of `p.funs` are
  exactly the definitions that calls reach. The other conditions are stated
  on these entries.
* `nonRecursive`: no call is recursive.
* `labelsUnique`: the labels of the bodies of the functions of `p` are pairwise
  distinct, so that a label names one statement of the program text.
* `stmtLabels`: `s` is a statement of a function body of `p`, such as a body
  itself or a statement inside one; or else the labels of `s` are pairwise
  distinct and distinct from those of the function bodies. In both cases a
  label names one statement of `s` and of the function bodies. Membership in
  `p.stmts` compares statements, not labels: a statement outside the program
  that reuses a label of the program does not meet it. -/
structure WellFormed (p : Program) (s : Stmt) : Prop where
  namesUnique : p.NamesUnique
  nonRecursive : p.NonRecursive
  labelsUnique : p.labels.Nodup
  stmtLabels : s ∈ p.stmts ∨ (s.labels ++ p.labels).Nodup

/-- The subject of the observations: a statement of the fragment, with its
program. -/
structure Subject where
  prog : Program
  stmt : Stmt
  wf : WellFormed prog stmt

/-! ## Statements of the fragment

A statement of a function body and a statement inside the observed statement
are in the fragment, for the same program. Later theorems that pass from a
statement to the body of a callee, or to a statement inside it, use these
lemmas to form the subject of the new statement. -/

theorem Stmt.mem_subs_self (s : Stmt) : s ∈ s.subs := by
  cases s <;> simp [Stmt.subs]

theorem Stmt.mem_subs_trans {s₁ s₂ s₃ : Stmt} (h₁ : s₁ ∈ s₂.subs)
    (h₂ : s₂ ∈ s₃.subs) : s₁ ∈ s₃.subs := by
  induction s₃ with
  | seq l a b iha ihb =>
    simp only [Stmt.subs, List.mem_cons, List.mem_append] at h₂ ⊢
    rcases h₂ with rfl | h₂ | h₂
    · simpa [Stmt.subs] using h₁
    · exact Or.inr (Or.inl (iha h₂))
    · exact Or.inr (Or.inr (ihb h₂))
  | ite l c a b iha ihb =>
    simp only [Stmt.subs, List.mem_cons, List.mem_append] at h₂ ⊢
    rcases h₂ with rfl | h₂ | h₂
    · simpa [Stmt.subs] using h₁
    · exact Or.inr (Or.inl (iha h₂))
    · exact Or.inr (Or.inr (ihb h₂))
  | loop l c body ih =>
    simp only [Stmt.subs, List.mem_cons] at h₂ ⊢
    rcases h₂ with rfl | h₂
    · simpa [Stmt.subs] using h₁
    · exact Or.inr (ih h₂)
  | _ =>
    simp only [Stmt.subs, List.mem_singleton] at h₂
    subst h₂
    exact h₁

/-- The labels of a statement inside `s` form a sublist of the labels of
`s`. -/
theorem Stmt.labels_sublist {s s' : Stmt} (h : s' ∈ s.subs) :
    s'.labels.Sublist s.labels := by
  induction s with
  | seq l a b iha ihb =>
    simp only [Stmt.subs, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | h
    · exact List.Sublist.refl _
    · exact (iha h).trans ((List.sublist_append_left _ _).cons l)
    · exact (ihb h).trans ((List.sublist_append_right _ _).cons l)
  | ite l c a b iha ihb =>
    simp only [Stmt.subs, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | h
    · exact List.Sublist.refl _
    · exact (iha h).trans ((List.sublist_append_left _ _).cons l)
    · exact (ihb h).trans ((List.sublist_append_right _ _).cons l)
  | loop l c body ih =>
    simp only [Stmt.subs, List.mem_cons] at h
    rcases h with rfl | h
    · exact List.Sublist.refl _
    · exact (ih h).cons l
  | _ =>
    simp only [Stmt.subs, List.mem_singleton] at h
    subst h
    exact List.Sublist.refl _

/-- The labels of a statement of a function body form a sublist of the labels
of the program. -/
theorem Program.labels_sublist {p : Program} {s : Stmt} (h : s ∈ p.stmts) :
    s.labels.Sublist p.labels := by
  simp only [Program.stmts, List.mem_flatMap] at h
  obtain ⟨d, hd, hs⟩ := h
  refine (Stmt.labels_sublist hs).trans ?_
  simp only [Program.labels, List.flatMap_def]
  exact List.sublist_flatten_of_mem (List.mem_map_of_mem hd)

/-- The body of a function that a call reaches is a statement of the
program. -/
theorem Program.body_mem_stmts {p : Program} {f : FunName} {fd : FunDef}
    (h : p.lookup f = some fd) : fd.body ∈ p.stmts := by
  obtain ⟨l₁, l₂, hl, -⟩ := List.lookup_eq_some_iff.mp h
  simp only [Program.stmts, List.mem_flatMap]
  exact ⟨(f, fd), by simp [hl], Stmt.mem_subs_self _⟩

/-- The labels of the observed statement are pairwise distinct. -/
theorem WellFormed.stmt_labels_nodup {p : Program} {s : Stmt}
    (h : WellFormed p s) : s.labels.Nodup := by
  rcases h.stmtLabels with hs | hs
  · exact h.labelsUnique.sublist (Program.labels_sublist hs)
  · exact hs.sublist (List.sublist_append_left _ _)

/-- A statement inside the observed statement is in the fragment. -/
theorem WellFormed.sub {p : Program} {s s' : Stmt} (h : WellFormed p s)
    (hs : s' ∈ s.subs) : WellFormed p s' := by
  refine ⟨h.namesUnique, h.nonRecursive, h.labelsUnique, ?_⟩
  rcases h.stmtLabels with h' | h'
  · left
    simp only [Program.stmts, List.mem_flatMap] at h' ⊢
    obtain ⟨d, hd, h'⟩ := h'
    exact ⟨d, hd, Stmt.mem_subs_trans hs h'⟩
  · right
    exact h'.sublist ((Stmt.labels_sublist hs).append (List.Sublist.refl _))

/-- The body of a function that a call reaches is in the fragment, with any
statement of the fragment for the same program. -/
theorem WellFormed.body {p : Program} {s : Stmt} {f : FunName} {fd : FunDef}
    (h : WellFormed p s) (hf : p.lookup f = some fd) : WellFormed p fd.body :=
  ⟨h.namesUnique, h.nonRecursive, h.labelsUnique,
    Or.inl (Program.body_mem_stmts hf)⟩

end ReuseModel
