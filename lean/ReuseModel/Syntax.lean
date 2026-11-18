/-!
# Syntax

The language of the model: whole-block loads and stores, sequencing,
conditionals, `while`, direct calls and return, and labelled assertions.

A value is an integer or a pointer to a whole block. There are no offsets into
a block, no arrays or structures, no pointer arithmetic and no casts between
pointers and integers. A program is in the fragment when its calls are not
recursive (`Program.NonRecursive`).
-/

namespace ReuseModel

/-- A block: a unit of memory that holds one value. A block can stand for a
global, a local of a caller or an existing heap allocation; the model does not
distinguish them. -/
abbrev Block := Nat

/-- A value: an integer, or a pointer to a block. The integer `0` serves as
the null pointer. -/
inductive Value where
  | int (n : Int)
  | ptr (b : Block)
  deriving DecidableEq, Repr

/-- A variable name. -/
abbrev Var := String

/-- A function name. -/
abbrev FunName := String

/-- A statement label. Every statement carries one, as every statement of
Frama-C has an identifier. Reach and Safety are observed by label. -/
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

/-- A program: its functions and the blocks of its global variables. -/
structure Program where
  funs : FunName → Option FunDef
  globals : Var → Option Block

/-- No call of the program is recursive: a rank on functions decreases along
every direct call. The language allows recursive programs, but they are
outside the fragment that the theorems of the model target. -/
def Program.NonRecursive (p : Program) : Prop :=
  ∃ rank : FunName → Nat, ∀ f fd, p.funs f = some fd →
    ∀ g ∈ fd.body.callees, rank g < rank f

end ReuseModel
