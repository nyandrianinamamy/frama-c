# Frame

Claims about the blocks that a statement does not access: its frame, in the
sense of [`GLOSSARY.md`](../../../GLOSSARY.md).

## Frame lemma with lexical sweeps

**Kind.** Proved in Lean.

**Claim.** At any finite prefix, an existing frame block has its entry
contents with the recorded lexical sweeps applied in order. This covers
before-statement visits, normal exits and prefixes ending in a fault.
The general form needs absence of ordinary writes to the block on the
selected prefix. It applies to a block already issued at entry, including
one with no live binding.

**Scope.** Whole blocks. A lexical scope allocates fresh locals and sweeps
them at scope exit, including on return. A sweep ends a local's lifetime
and marks pointers to that identifier in surviving values. The marker
retains the target identifier and a dereference of the marked value faults.
The step function also marks a pending return value that points to the
departing local. Ordinary call cleanup uses release without a sweep in
this model. There is no heap or VLA sweep. Concrete execution includes
lexical scopes executed inside calls. The semantics sweeps the locals of
the scope being unwound. A lexical sweep event alone cannot establish
that the cached unit owns those locals. The ownership check for admission
belongs to #44.

**Declarations.** [Frame](../../../lean/ReuseModel/Frame.lean),
[Memory](../../../lean/ReuseModel/Memory.lean),
[Semantics](../../../lean/ReuseModel/Semantics.lean) and
[Replay](../../../lean/ReuseModel/Replay.lean).

**Statements and axiom output.**

```lean
Value.escape : Block → Value → Value
'ReuseModel.Value.escape' does not depend on any axioms

@Memory.sweep : {M : Type} → [self : Memory M] → M → Block → M
'ReuseModel.Memory.sweep' does not depend on any axioms

@Memory.load_sweep_same : ∀ {M : Type} [self : Memory M] (m : M) (b : Block), Memory.load (Memory.sweep m b) b = none
'ReuseModel.Memory.load_sweep_same' does not depend on any axioms

@Memory.load_sweep_other : ∀ {M : Type} [self : Memory M] (m : M) (b b' : Block),
  b' ≠ b → Memory.load (Memory.sweep m b) b' = Option.map (Value.escape b) (Memory.load m b')
'ReuseModel.Memory.load_sweep_other' does not depend on any axioms

@Memory.issued_sweep : ∀ {M : Type} [self : Memory M] (m : M) (b b' : Block),
  Memory.Issued m b' → Memory.Issued (Memory.sweep m b) b'
'ReuseModel.Memory.issued_sweep' does not depend on any axioms

@sweepAll : {M : Type} → [Memory M] → M → List Block → M
'ReuseModel.sweepAll' does not depend on any axioms

applySweeps : List Block → Option Value → Option Value
'ReuseModel.applySweeps' does not depend on any axioms

sweepTargets : List Event → List Block
'ReuseModel.sweepTargets' depends on axioms: [propext]

@stepNext : {M : Type} → [Memory M] → Cont → Env → M → List Event × Config M
'ReuseModel.stepNext' does not depend on any axioms

@AllocatorAgreement.sweep : ∀ {M : Type} [inst : Memory M] (self : AllocatorAgreement M) {m n : M} (b : Block),
  self.rel m n → self.rel (Memory.sweep m b) (Memory.sweep n b)
'ReuseModel.AllocatorAgreement.sweep' does not depend on any axioms

@frame_of_not_written : ∀ {M : Type} [inst : Memory M] {p : Program} {s : Stmt} {σ : State M} {b : Block},
  Memory.Issued σ.mem b →
    ∀ {evs : List Event} {c : Config M},
      Steps p (Config.entry s σ) evs c →
        (∀ (e : Event), e ∈ evs → ¬e.Writes b) →
          Memory.load c.mem b = applySweeps (sweepTargets evs) (Memory.load σ.mem b)
'ReuseModel.frame_of_not_written' depends on axioms: [propext, Quot.sound]

@frame_lemma : ∀ {M : Type} [inst : Memory M] {t : Subject} {σ : State M} {b : Block},
  Live σ.mem b →
    InFrame t σ b →
      ∀ {evs : List Event} {c : Config M},
        Prefix t σ evs c → Memory.load c.mem b = applySweeps (sweepTargets evs) (Memory.load σ.mem b)
'ReuseModel.frame_lemma' depends on axioms: [propext, Quot.sound]

@sweep_target_fresh : ∀ {M : Type} [inst : Memory M] {t : Subject} {σ : State M} {evs : List Event} {c : Config M},
  Prefix t σ evs c → ∀ {target : Block}, target ∈ sweepTargets evs → ¬Memory.Issued σ.mem target
'ReuseModel.sweep_target_fresh' depends on axioms: [propext, Quot.sound]

applySweeps_eq_iff : ∀ (targets : List Block) (v : Option Value),
  applySweeps targets v = v ↔ ∀ (target : Block), target ∈ targets → v ≠ some (Value.ptr target)
'ReuseModel.applySweeps_eq_iff' depends on axioms: [propext, Quot.sound]

@frame_no_sweep_rewrite : ∀ {M : Type} [inst : Memory M] {t : Subject} {σ : State M} {b : Block},
  Memory.Issued σ.mem b →
    (∀ (target : Block), Memory.load σ.mem b = some (Value.ptr target) → Memory.Issued σ.mem target) →
      ∀ {evs : List Event} {c : Config M},
        Prefix t σ evs c → (∀ (e : Event), e ∈ evs → ¬e.Writes b) → Memory.load c.mem b = Memory.load σ.mem b
'ReuseModel.frame_no_sweep_rewrite' depends on axioms: [propext, Quot.sound]
```

**Hypotheses.**

| Hypothesis or parameter | Kind and scope |
| --- | --- |
| `[Memory M]` | Model interface, proved in Lean for `FunMem`. A sweep removes its target, marks exactly the unmarked pointers to that target in surviving blocks and preserves issuance. Creation uses a never-issued identity. |
| `b' ≠ b` in `Memory.load_sweep_other` | Local model premise. The observed holder is distinct from the sweep target. |
| `Memory.Issued m b'` in `Memory.issued_sweep` | Local model premise. Issuance of that block before the sweep is preserved. |
| `self : AllocatorAgreement M` and `self.rel m n` in its sweep law | Model parameter and local premise. The law holds for `FunMem.allocatorAgreement` by equality of the next fresh identifier. The class of operations preserving that equality now includes lexical sweeps. |
| `t : Subject` | Model parameter with a `WellFormed` fragment proof. Unique names, nonrecursive calls and unique labels have the same definitions as in the original frame entry below. The general frame form takes a raw `p` and `s`. |
| `σ`, `b`, `evs`, `c` | Model parameters. Entry memory and bindings, observed block, recorded events and endpoint. |
| `Live σ.mem b` or `Memory.Issued σ.mem b` | Local model premise. The frame lemma uses liveness to obtain issuance. The general and no-rewrite forms take issuance directly. For old live cells in an Eva frame, correspondence is an OCaml obligation. |
| `InFrame t σ b` | Local model premise. No finite prefix performs an ordinary read or write of `b`. Coverage of those accesses by the collector is an [OCaml obligation](body-access.md#whole-block-observations-and-exits). |
| `∀ e ∈ evs, ¬ e.Writes b` | Local model premise. Only designated writes on this prefix matter to the general frame and no-rewrite lemmas. At a normal exit, coverage by `W_exit` supplies this premise for a block outside that overlay. For an Inner query use the writes up to that visit. |
| `Steps p (Config.entry s σ) evs c` or `Prefix t σ evs c` | Local model premise. The events and endpoint come from the same execution. `Prefix` is `Steps` for the program and statement in the subject. |
| `target ∈ sweepTargets evs` | Local model premise. The target is of a lexical sweep on the selected prefix. Matching this provenance at admission is an OCaml obligation below. |
| `∀ target, Memory.load σ.mem b = some (Value.ptr target) → Memory.Issued σ.mem target` | Local model premise and a sufficient OCaml obligation for the no-rewrite path. It applies to the current state and includes previously issued, now dead targets. |
| `targets` and `v` in `applySweeps_eq_iff` | Unrestricted model parameters. The equivalence compares the fold to its input and characterises exactly when the fold is the identity. |

**Depends on.** The memory laws, the scope continuation and step rules,
and the proof invariant that an entry-issued block cannot become a local
of a later call or scope. Thus each swept identifier was unissued at entry.
A sweep can change an untouched holder even though the write bound covers
all designated writes.

**Evidence.** Tree of `lean/` `baaacef349ee92e373475ca88b596619282b3ed2` at
commit `fa1175a44de40098071cb2ada6674a2fa875876f`. `cd lean && lake build --wfail`
completed with exit status 0 using the pinned Lean 4.28.0 toolchain.
CI: [run 44428598174](https://github.com/nyandrianinamamy/frama-c/actions/runs/44428598174) succeeded on this tree.

**Checked cases.** The fixture allocates block 2 in an inner scope, stores
its address in block 0 and leaves the scope. Block 0 becomes escaped and
block 2 is absent. Untouched block 1 pointing to the already-issued block 0
is preserved at the next visit and at normal exit. In the negative case
block 1 instead holds an unmarked pointer to the next fresh identifier at
entry and changes despite satisfying `InFrame`. The return case checks the
marker on a pointer carried out by the return itself. A sound entry
from the same fixture matches a distinct member with `W_exit = {0}`.
The member exits normally and block 1 changes from `ptr 2` to
`escaped 2` without an ordinary write. The nested-call fixture records
a callee's lexical sweep in the caller's trace.

```lean
Checks.own_local_sweep : (run Checks.sweepProg 4 (Config.entry Checks.sweepStmt Checks.sweepInput)).fst =
    [Event.scopeEnter 2, Event.write 0, Event.sweep 2] ∧
  Memory.load (run Checks.sweepProg 4 (Config.entry Checks.sweepStmt Checks.sweepInput)).snd.mem 0 =
      some (Value.escaped 2) ∧
    Memory.load (run Checks.sweepProg 4 (Config.entry Checks.sweepStmt Checks.sweepInput)).snd.mem 2 = none
'Checks.own_local_sweep' depends on axioms: [propext]

Checks.own_local_frame_unchanged : InFrame Checks.sweepSubj Checks.sweepInput 1 ∧
  Memory.load (Checks.sweepRun Checks.sweepInput 5).snd.mem 1 = some (Value.ptr 0) ∧
    Memory.load (Checks.sweepRun Checks.sweepInput 7).snd.mem 1 = some (Value.ptr 0)
'Checks.own_local_frame_unchanged' depends on axioms: [propext, Quot.sound]

Checks.future_pointer_needs_rewrite : InFrame Checks.sweepSubj Checks.futurePointerInput 1 ∧
  Live Checks.futurePointerInput.mem 1 ∧
    ¬Memory.Issued Checks.futurePointerInput.mem 2 ∧
      sweepTargets (Checks.sweepRun Checks.futurePointerInput 5).fst = [2] ∧
        Memory.load Checks.futurePointerInput.mem 1 = some (Value.ptr 2) ∧
          Memory.load (Checks.sweepRun Checks.futurePointerInput 5).snd.mem 1 = some (Value.escaped 2)
'Checks.future_pointer_needs_rewrite' depends on axioms: [propext, Quot.sound]

Checks.return_sweeps_local : (run Checks.sweepProg 4
        (Config.entry (Stmt.scope 10 [("local", 9)] (Stmt.ret 11 (some (Expr.addr "local")))) Checks.sweepInput)).fst =
    [Event.scopeEnter 2, Event.sweep 2] ∧
  Checks.outcomeOf?
      (run Checks.sweepProg 4
          (Config.entry (Stmt.scope 10 [("local", 9)] (Stmt.ret 11 (some (Expr.addr "local"))))
            Checks.sweepInput)).snd =
    some (Outcome.returned (some (Value.escaped 2)))
'Checks.return_sweeps_local' depends on axioms: [propext]

Checks.matching_frame_holder_rewritten : Checks.sweepEntry.Sound FunMem.allocatorAgreement ∧
  Checks.sweepEntry.Matches FunMem.allocatorAgreement Checks.futurePointerInput.mem ∧
    Checks.futurePointerInput.mem ≠ Checks.sweepInput.mem ∧
      Checks.sweepEntry.footprint.exitWrites = [0] ∧
        InFrame Checks.sweepSubj Checks.futurePointerInput 1 ∧
          Memory.Issued Checks.futurePointerInput.mem 1 ∧
            Exit Checks.sweepSubj Checks.futurePointerInput Outcome.completed
                (Checks.sweepRun Checks.futurePointerInput 7).snd.mem ∧
              (Checks.sweepRun Checks.futurePointerInput 7).fst = [Event.scopeEnter 2, Event.write 0, Event.sweep 2] ∧
                Memory.load Checks.futurePointerInput.mem 1 = some (Value.ptr 2) ∧
                  Memory.load (Checks.sweepRun Checks.futurePointerInput 7).snd.mem 1 = some (Value.escaped 2)
'Checks.matching_frame_holder_rewritten' depends on axioms: [propext, Quot.sound]

Checks.nested_scope_sweep_in_caller : ¬Checks.nestedSweepBody ∈ Checks.nestedSweepCall.subs ∧
  (run Checks.nestedSweepProgram 10 (Config.entry Checks.nestedSweepBody Checks.sweepInput)).fst =
      [Event.scopeEnter 2, Event.write 0, Event.sweep 2] ∧
    (run Checks.nestedSweepProgram 10 (Config.entry Checks.nestedSweepCall Checks.sweepInput)).fst =
        (run Checks.nestedSweepProgram 10 (Config.entry Checks.nestedSweepBody Checks.sweepInput)).fst ∧
      Memory.load (run Checks.nestedSweepProgram 10 (Config.entry Checks.nestedSweepCall Checks.sweepInput)).snd.mem 0 =
        some (Value.escaped 2)
'Checks.nested_scope_sweep_in_caller' depends on axioms: [propext]
```

## Admission condition for sweeps of own locals

**Kind.** OCaml obligation, open.

**Condition for #44.** Admit a sweep only at the exit of an inner lexical
scope of the cached body, targeting the body's own departing locals.
The collector must establish this ownership, including when a trace
could contain events from a nested call.

For each current concrete memory admitted by the lookup, each skipped
prefix, and each issued entry block that the prefix has not ordinarily
written and whose value will be taken from the current input, require

```lean
∀ target ∈ sweepTargets evs, Memory.load σ.mem b ≠ some (Value.ptr target)
```

This is exactly the condition for reusing the unchanged entry value of
that block in the model, by `frame_of_not_written` and
`applySweeps_eq_iff`. A sufficient condition is that each unmarked pointer
in those holders targets an identifier already issued at entry, while the
skipped sweep targets represent lifetimes begun during the body. This
sufficient condition is the current-input premise of
`frame_no_sweep_rewrite`.
If a current frame holder may contain an unmarked pointer to a swept
target and unchanged reuse cannot be justified, replay on that holder
would be needed. That case is refused here. A producer-only holder list
cannot establish this condition. The condition does not require pointer
closure of the matching key in the model.

On a normal exit, an existing holder changed by a designated write is
covered by the normal-exit overlay `W_exit`. The producing Exit state used
for that overlay must include the effect of the sweep on the holder.
A public Inner answer may use the frame rule only for a prefix where the
holder is untouched, with the sweeps already performed at that visit.
The outer call's finalization runs in the caller. A nested call is
currently refused by the collector.

**Eva symbols and source evidence.**
`Transfer_stmt.leave_scope` calls `Cvalue_domain.State.leave_scope`.
`Locals_scoping.make_escaping_fundec` selects departing referenced
non-temporaries, reports `Body_access.Sweep` through `unknown_access`,
and applies `make_escaping` to the candidate holders and the null base,
with a full map scan when the holder set is Top. `Transfer_stmt.do_one_call`
performs the outer cleanup. The observed collector disposition is still
`sweep`. See [Body access](body-access.md#refusal-and-reporting) and
[Entries from fresh bodies](cache-producer.md#key-and-footprint-from-the-collector).

**Open.** The checks here use fresh concrete identifiers for each lexical
lifetime. Eva's bases identify variables, so #44 must give the
correspondence for repeated visits to a lexical scope, preceding
activations, unmarked versus already-escaping references, and the
concretisation of offsetmaps and unknown values. Excluding recursion
helps separate the body from an active outer instance of the same
body. The holder condition still needs a proof when a lexical scope has
already run in a loop or on an earlier call. #44 needs an admission check or argument for the current frame,
coverage of the holder updates and their exit bindings, and an Eva
regression with a written holder checked after the sweep. The
whole-block proof is checked. The argument for offsets is open. No Eva
regression for sweep admission was run here.

## Reading a marked holder

**Kind.** Known difference.

After `{ int t = 9; holder = &t; }`, the model reads the marked value
in `return holder == 0;` and returns `0` normally. The scalar read in
Eva's `eval_one_loc` checks the escaping flag through
`indeterminate_alarms`. The review's C run reported a sure
escaping-address alarm at the read and no final state.
[Source](../../../plugins/eva/src/domains/cvalue/cvalue_queries.ml#L29).

The model's Safety, Reach and Exit arguments do not cover an Eva body
that evaluates a marked holder. Add this case to the known differences
work, with a correspondence argument and a replayable Eva fixture for
any support it claims. [Known differences from the model (#58)](https://github.com/nyandrianinamamy/frama-c/issues/58).

**Lean evidence.** The comparison used the same tree and build as the
[frame checks](#frame-lemma-with-lexical-sweeps). The Eva observation above
comes from the review run.

```lean
Checks.swept_holder_comparison_returns : (run Checks.sweepProg 9
        (Config.entry Checks.sweptHolderComparison Checks.sweepInput)).fst =
    [Event.scopeEnter 2, Event.write 0, Event.sweep 2, Event.read 0] ∧
  Checks.outcomeOf? (run Checks.sweepProg 9 (Config.entry Checks.sweptHolderComparison Checks.sweepInput)).snd =
    some (Outcome.returned (some (Value.int 0)))
'Checks.swept_holder_comparison_returns' depends on axioms: [propext]
```

## Frame lemma without sweeps

This entry records the earlier theorem at its cited historical tree.
The current statement of `frame_lemma` is the one above.


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

- Checked revision: commit `0e3b43669587f1c9c2cbc1e5ae8ad6c681f12f2a`. Tree of
  `lean/` at that commit: `a95aed2447ff8818235d38c22ffa02ebd72ba43c`.
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
  ran on the checked revision and succeeded
  ([run 44354462356](https://github.com/nyandrianinamamy/frama-c/actions/runs/44354462356)).
  A later push of two commits that change no file under `lean/` started no
  run.
- Rebuilt at tree `8fb8b87666889ddca7376bdd0555803062ab973a` (commit
  `fb938739594412912b0bc9de1e8a28d9454b32af`), which adds the domain laws
  ([Domain laws](domain-laws.md), [Matching](matching.md)) and changes no
  file that the lemma depends on: `ReuseModel/Syntax.lean`, `Memory.lean`,
  `Semantics.lean`, `Observations.lean` and `Frame.lean` are those of the
  checked tree. Same command, run on 2026-11-18 on an extraction of that
  commit, exit status 0; `#print axioms ReuseModel.frame_lemma` gives
  `[propext, Quot.sound]`, as above. CI: [run 44383251659](https://github.com/nyandrianinamamy/frama-c/actions/runs/44383251659) succeeded on that tree.
- Rebuilt at tree `a84123b158f292d1debae406ac75950ee89cb87a` (commit
  `b1fa74dbca1ca91aff261a5f268583c35d6c740f`), which adds [entry
  construction](entry.md). The files listed in the preceding rebuild are
  identical. Same command on an extraction of that commit on 2026-11-18,
  exit status 0. The axiom output is unchanged. CI: [run 44402277212](https://github.com/nyandrianinamamy/frama-c/actions/runs/44402277212) succeeded on this tree.

**Open obligations.** None for the claim in the model. To use the lemma for a
cache entry of Eva, Eva's footprint must cover the blocks that the statement
reads or writes. That is an OCaml obligation of the claims that will use this
lemma, and it is not recorded here.
