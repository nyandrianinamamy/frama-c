# Frame

Claims about the blocks that a statement does not access: its frame, in the
sense of [`GLOSSARY.md`](../../../GLOSSARY.md).

## Frame lemma without sweeps

**Kind.** Proved in Lean.

**Claim.** Let `s` be a statement of a program `p`, started from a state `σ`
(a local environment and a memory), and let `b` be a block that is live in the
memory of `σ`. If no finite prefix of the execution of `s` from `σ` reads or
writes `b`, then at every visit inside `s`, the visits inside the calls that `s`
makes included, `b` has the value it had at entry.

**Scope.** The model only. Its language, memory and observations are described
in [`lean/README.md`](../../../lean/README.md): whole blocks, no offsets, no
pointer arithmetic, no casts between pointers and integers, and no sweep. The
claim holds for every memory that meets the laws of the interface `Memory`. The
frame is defined from the reads and writes of the execution itself, not from an
analysis. A visit is a configuration of a finite prefix, so the visits before a
fault and inside a call that does not return are covered. The claim does not
need the program to be nonrecursive.

**Declaration.** `ReuseModel.frame_lemma`, in
[`lean/ReuseModel/Frame.lean`](../../../lean/ReuseModel/Frame.lean).

**Statement**, as Lean prints it (`#check @ReuseModel.frame_lemma`):

```lean
@frame_lemma : ∀ {M : Type} [inst : Memory M] {p : Program} {s : Stmt} {σ : State M} {b : Block},
  Live σ.mem b →
    InFrame p s σ b → ∀ {l : Label} {env : Env} {m : M}, Visit p s σ l env m → Memory.load m b = Memory.load σ.mem b
```

**Hypotheses.**

1. `[Memory M]`: the memory meets the laws of the interface `Memory`, on
   access, faults and lifetime
   ([`lean/ReuseModel/Memory.lean`](../../../lean/ReuseModel/Memory.lean)).
   The memory `FunMem` in the same file meets them, so the hypothesis can be
   satisfied.
2. `Live σ.mem b`, that is `(Memory.load σ.mem b).isSome = true`: `b` exists at
   entry.
3. `InFrame p s σ b`, that is
   `∀ evs c, Prefix p s σ evs c → ∀ e ∈ evs, ¬ e.Accesses b`: no finite prefix
   of the execution of `s` from `σ` reads or writes `b`. `Prefix p s σ` is
   `Steps p (Config.entry s σ)`. `Event.Accesses` holds for the read and write
   events on `b`; the start and end of the lifetime of a callee's locals are
   not accesses.
4. `Visit p s σ l env m`: some finite prefix ends at a configuration
   `Config.run st k env m` with `st.label = l`, where the statement `st` is
   about to execute in environment `env` and memory `m`.

The proof uses only the writes in hypothesis 3. The general form
`ReuseModel.frame_of_not_written`, in the same file, needs only that `b` was
issued before entry and that the prefix at hand does not write `b`. It holds
at every configuration of that prefix, final ones included.

**Depends on.** No other entry of this record. Within the model: the laws
`issued_of_load`, `load_store_other`, `issued_store`, `not_issued_create`,
`load_create_other`, `issued_create`, `load_release_other` and
`issued_release` of `Memory`, and the definitions of the semantics.

**Evidence.**

- Checked revision: commit `04cebc882a4006de0823171ac5a674a3ba1a3744`. Tree of
  `lean/` at that commit: `958b3150e95eab1a6a4c1dacc082f30da665ffcf`.
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
  `lean/Checks/Examples.lean`, applies the lemma to a statement whose callee
  never returns, with `InFrame` proved for a global that the statement does
  not access.
- CI: the workflow `.github/workflows/lean-model.yml` runs the same command. It
  had not run on the checked revision when this entry was written.

**Open obligations.** None for the claim in the model. To use the lemma for a
cache entry of Eva, Eva's footprint must cover the blocks that the statement
reads or writes. That is an OCaml obligation of the claims that will use this
lemma, and it is not recorded here.
