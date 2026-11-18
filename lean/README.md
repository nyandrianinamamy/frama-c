# Lean model of statement reuse

This directory holds the Lean reference model for the reuse of cache entries in
Eva. It defines a small language, a concrete memory, executions and the
observations that a cache entry makes claims about, and it proves theorems
about them. The first theorem is the frame lemma without sweeps.

The theorems are about the model. They do not verify the OCaml code of Eva.
Whether Eva meets the hypotheses of a theorem is a separate question, answered
claim by claim in the correspondence record,
[`docs/eva/reuse-correspondence/`](../docs/eva/reuse-correspondence/README.md).

The model is written for this effort. Its published basis is the ECOOP 2025
paper *Reusing Caches and Invariants for Efficient and Sound Incremental Static
Analysis* ([LIPIcs, ECOOP 2025, paper 28](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2025.28)).

## Build

From the root of a clean checkout, with [elan](https://github.com/leanprover/elan)
installed:

```sh
cd lean && lake build --wfail
```

elan installs the toolchain pinned in `lean-toolchain` on first use. Run the
command from this directory: elan selects the toolchain from the
`lean-toolchain` file of the current directory, and `lake --dir lean` run from
the repository root would use elan's default toolchain instead.

The build fails when:

- a proof does not check;
- Lean emits a warning (`--wfail`), which includes `declaration uses 'sorry'`;
- a theorem listed in `Checks/Axioms.lean` depends on an axiom other than
  `propext`, `Classical.choice` and `Quot.sound` (`#check_axioms`).

The build output shows the `#print axioms` result of each listed theorem, also
when the modules are already built (Lake replays their messages).

The ordinary Frama-C build does not need Lean: the root `dune` file lists the
directories that Dune reads, and `lean` is not among them.

## Pins

- Toolchain: `leanprover/lean4:v4.28.0`, in `lean-toolchain`.
- Packages: none. The model uses Lean's core library only, and
  `lake-manifest.json` lists no package.
- CI: [`.github/workflows/lean-model.yml`](../.github/workflows/lean-model.yml)
  installs elan 4.2.4 from its release archive, checked against a SHA-256
  digest, and pins `actions/checkout` to a commit. It runs `lake build --wfail`
  on a push or a pull request that changes a file under `lean/` or the workflow
  itself, and on manual dispatch. Other changes do not start it.

## Contents

| File | Content |
|---|---|
| `ReuseModel/Syntax.lean` | Blocks, values, expressions, statements, programs; `Program.NonRecursive` |
| `ReuseModel/Memory.lean` | The memory interface `Memory` with its laws; the memory `FunMem`, which meets them |
| `ReuseModel/Semantics.lean` | Events, evaluation, configurations, the step function, executions (`run`) and finite prefixes (`Steps`, `Prefix`) |
| `ReuseModel/Observations.lean` | Exit, Reach, Safety and visits |
| `ReuseModel/Frame.lean` | `InFrame`, `frame_of_not_written`, `frame_lemma` |
| `Checks/AxiomCheck.lean` | The `#check_axioms` command |
| `Checks/Axioms.lean` | `#print axioms` and `#check_axioms` for each theorem |
| `Checks/Examples.lean` | Aliasing, a dangling pointer after a return, and a call that does not return, on which `frame_lemma` is applied |

## What the model contains

- **Language.** Whole-block loads and stores, sequencing, conditionals,
  `while`, direct calls, return and labelled assertions. Every statement
  carries a label, which identifies it in the observations.
- **Memory.** Generic blocks, one value per block. A block can stand for a
  global, a caller's local or an existing heap allocation. Two pointers to the
  same live block alias. A call creates a block for each parameter and local of
  the callee; at the return these blocks go out of scope. An access to a block
  that is not live faults. Identifiers are not reused, so a pointer to a block
  that went out of scope stays dangling. Going out of scope rewrites no other
  block: the model has no sweep.
- **Executions.** A deterministic small-step semantics whose continuation holds
  the call stack. Each step reports the reads and writes it performs, and the
  start and end of the lifetime of the callee's locals. An execution iterates
  the step function; a finite prefix is a finite sequence of steps. The two
  coincide (`steps_iff_run`).
- **Observations.** Exit on normal ends of the statement. Reach and Safety on
  every finite prefix, so they include the visits before a fault and inside a
  call that does not return. Safety covers run-time alarms and labelled
  assertions.

## What the model leaves out

- Offsets into a block, arrays and structures, pointer arithmetic, and casts
  between pointers and integers.
- Recursion: the semantics runs recursive programs, but the fragment of the
  model is the programs that satisfy `Program.NonRecursive`. The frame lemma
  does not need this hypothesis.
- Eva's iteration strategy, and any abstract domain: there is no analyzer in
  the model.
- Creation and release of heap allocations during a statement. Heap blocks that
  exist at entry are covered.
- Reads of uninitialized values (every local is declared with an initial
  value) and integer overflow (integers are unbounded).
