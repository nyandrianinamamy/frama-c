/-!
# Syntax

The language of the model: whole-block loads and stores, sequencing,
conditionals, `while`, direct calls and return, and labelled assertions.

A value is an integer or a pointer to a whole block. There are no offsets into
a block, no arrays or structures, no pointer arithmetic and no casts between
pointers and integers.

The fragment of the model is given by `WellFormed`: each function is defined
once, no call is recursive, and the labels of the observed statement and of the
function bodies are pairwise distinct. A `Subject` bundles a program, the
observed statement and a proof that they are in the fragment; the observations
and the frame lemma are stated for subjects.
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
names one statement of the program text. -/
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
  deriving Repr

/-- Left-hand sides of assignments. A store overwrites a whole block. -/
inductive LExpr where
  /-- The block of a variable. -/
  | var (x : Var)
  /-- `*e`: the block that `e` points to. -/
  | deref (e : Expr)
  deriving Repr

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
  deriving Repr

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
  exactly the definitions that calls reach. The other two conditions are
  stated on these entries.
* `nonRecursive`: no call is recursive.
* `labelsUnique`: the labels of `s` and of the bodies of the functions of `p`
  are pairwise distinct, so that a label names one statement. The observed
  statement is therefore not a statement of a function body. -/
structure WellFormed (p : Program) (s : Stmt) : Prop where
  namesUnique : p.NamesUnique
  nonRecursive : p.NonRecursive
  labelsUnique : (s.labels ++ p.labels).Nodup

/-- The subject of the observations: a statement of the fragment, with its
program. -/
structure Subject where
  prog : Program
  stmt : Stmt
  wf : WellFormed prog stmt

end ReuseModel
