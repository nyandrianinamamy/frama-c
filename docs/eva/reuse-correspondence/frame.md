# Frame

Claims about the blocks that a statement does not access: its frame, in the
sense of [`GLOSSARY.md`](../../../GLOSSARY.md).

## Frame lemma without sweeps

**Kind.** Proved in Lean.

**Claim.** Let `s` be a statement of a program `p` in the fragment of the
model: each function is defined once, no call is recursive, the labels of the
function bodies are pairwise distinct, and `s` is either a statement of a
function body (the body itself or a statement inside it) or a statement whose
labels are pairwise distinct and distinct from those of the function bodies.
Let `s` start from a state `σ` (a local environment and a memory), and let `b`
be an existing block: it has a value in the memory of `σ`. If no finite prefix
of the execution of `s` from `σ` reads or writes `b`, then at every visit
inside `s`, the visits inside the calls that `s` makes included, `b` has the
value it had at entry.

**Scope.** The model only. Its language, memory and observations are described
in [`lean/README.md`](../../../lean/README.md): whole blocks, no offsets, no
pointer arithmetic, no casts between pointers and integers, and no sweep. The
claim holds for every memory that meets the laws of the interface `Memory`. The
frame is defined from the reads and writes of the execution itself, not from an
analysis. A visit is a configuration of a finite prefix, so the visits before a
fault and inside a call that does not return are covered. The claim is stated
for programs of the fragment, as the observations are; its proof does not use
the fragment conditions. The statement `s` can be the body of a function of
`p`, a statement inside such a body, or a statement outside the function
bodies.

**Declaration.** `ReuseModel.frame_lemma`, in
[`lean/ReuseModel/Frame.lean`](../../../lean/ReuseModel/Frame.lean).

**Statement**, as Lean prints it for `open ReuseModel` followed by
`#check @frame_lemma`:

```lean
@frame_lemma : ∀ {M : Type} [inst : Memory M] {t : Subject} {σ : State M} {b : Block},
  Live σ.mem b →
    InFrame t σ b → ∀ {l : Label} {env : Env} {m : M}, Visit t σ l env m → Memory.load m b = Memory.load σ.mem b
```

**Hypotheses.**

1. `[Memory M]`: the memory meets the laws of the interface `Memory`, on
   access, faults and lifetime
   ([`lean/ReuseModel/Memory.lean`](../../../lean/ReuseModel/Memory.lean)).
   The memory `FunMem` in the same file meets them, so the hypothesis can be
   satisfied.
2. `t : Subject`: a program `t.prog`, the observed statement `t.stmt`, and a
   proof `t.wf : WellFormed t.prog t.stmt`
   ([`lean/ReuseModel/Syntax.lean`](../../../lean/ReuseModel/Syntax.lean)).
   `WellFormed` has four fields: `namesUnique`, each function is defined once;
   `nonRecursive`, some rank on function names decreases along every direct
   call; `labelsUnique`, the labels of the function bodies are pairwise
   distinct; `stmtLabels`, `t.stmt ∈ t.prog.stmts` or the labels of `t.stmt`
   and of the function bodies are pairwise distinct together.
   `Program.stmts` lists each function body and the statements it contains,
   and membership compares statements, not labels. The statement `s` of the
   claim is `t.stmt` and the program `p` is `t.prog`.
3. `Live σ.mem b`, that is `(Memory.load σ.mem b).isSome = true`: `b` exists at
   entry.
4. `InFrame t σ b`, that is
   `∀ evs c, Prefix t σ evs c → ∀ e ∈ evs, ¬ e.Accesses b`: no finite prefix
   of the execution of `t.stmt` from `σ` reads or writes `b`. `Prefix t σ` is
   `Steps t.prog (Config.entry t.stmt σ)`. `Event.Accesses` holds for the read
   and write events on `b`; the start and end of the lifetime of a callee's
   locals are not accesses.
5. `Visit t σ l env m`: some finite prefix ends at a configuration
   `Config.run st k env m` with `st.label = l`, where the statement `st` is
   about to execute in environment `env` and memory `m`.

The proof uses only the writes in hypothesis 4; it does not use `t.wf`. The
general form `ReuseModel.frame_of_not_written`, in the same file, is stated for
any program `p` and statement `s`, over `Steps p (Config.entry s σ)`. It needs
only that `b` was issued before entry and that the steps at hand do not write
`b`. It holds at every configuration reached by these steps, final ones
included.

**Depends on.** No other entry of this record. Within the model: the laws
`issued_of_load`, `load_store_other`, `issued_store`, `not_issued_create`,
`load_create_other`, `issued_create`, `load_release_other` and
`issued_release` of `Memory`, and the definitions of the semantics.

**Evidence.**

- Checked revision: commit `ef89548104e2e83a4b285bb6e4faf0bc5e2d6ed3`. Tree of
  `lean/` at that commit: `a87723bde6d2f69d08574a959f9ee0e1ba611424`.
  Toolchain: `leanprover/lean4:v4.28.0` (Lean 4.28.0, commit `7e01a1bf5c70`).
- Command: `cd lean && lake build --wfail`, run on 2026-11-18 in a fresh
  shallow clone of that commit. Exit status 0.
- `#print axioms ReuseModel.frame_lemma`:

  ```
  'ReuseModel.frame_lemma' depends on axioms: [propext, Quot.sound]
  ```

  These are standard axioms of Lean. There is no `sorryAx` and no custom
  axiom. `#check_axioms` in `lean/Checks/Axioms.lean` checks this at each
  build.
- The hypotheses can be met together: `Checks.spin_frame`, in
  `lean/Checks/Examples.lean`, applies the lemma to the subject `spinSubj`,
  whose fragment conditions are checked by `decide`, and whose statement calls
  a function that never returns. `InFrame` is proved there for a global that
  the statement does not access.
- A function body and a statement inside one form subjects:
  `Checks.nestBodySubj` and `Checks.nestCallSubj`, in
  `lean/Checks/Fragment.lean`, and `Checks.spinBodySubj`, in
  `lean/Checks/Examples.lean`, on which Reach and Safety are observed inside
  the body. In `lean/ReuseModel/Syntax.lean`, `ReuseModel.WellFormed.body`
  proves that, for any subject, the body of a function that a call reaches is
  in the fragment with the same program, and `ReuseModel.WellFormed.sub` proves
  the same for a statement inside the observed statement. Their axioms are
  `propext` and `Quot.sound`.
- Programs and statements outside the fragment have no subject:
  `lean/Checks/Fragment.lean` proves `¬ WellFormed` for a statement in which
  one label names two statements, for a statement outside the function bodies
  that reuses one of their labels, for every statement of a program whose two
  function bodies share a label, and for a directly recursive and a mutually
  recursive program, each failing one condition only. The bodies of the
  recursive programs are rejected too.
- CI: the workflow `.github/workflows/lean-model.yml` runs the same command. It
  had not run on the checked revision when this entry was written.

**Open obligations.** None for the claim in the model. To use the lemma for a
cache entry of Eva, Eva's footprint must cover the blocks that the statement
reads or writes. That is an OCaml obligation of the claims that will use this
lemma, and it is not recorded here.
