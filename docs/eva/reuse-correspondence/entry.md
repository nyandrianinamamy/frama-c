# Entry construction

## Sound entry from producer soundness and coverage

**Kind.** Proved in Lean.

**Claim.** An entry with a non-empty stored input, sound producer results,
and covered reads and writes is sound for each execution satisfying
`entry.Matches a m`. Under that stronger match, the key need only contain
`R ∪ (W_exit \ W_sure)`. Safety covers alarms and failed assertions on
every finite prefix, and Reach covers every visit. Exit supplies a memory covered by the
stored output that agrees with the current output on the possible normal-exit
writes, for the same outcome. The footprint bounds and the certain-write
guarantee also hold for the matching execution. The [frame lemma](frame.md#frame-lemma-with-lexical-sweeps)
gives the complementary condition on the current caller's frame.

**Scope.** Whole blocks and the execution of a single subject with fixed
entry bindings. A matching memory has one producing witness that agrees on
the key, the liveness of the recorded write targets, and allocation state.
The liveness condition preserves whether a store succeeds even when the
old content is omitted. In the load fixture, a pointer to a dead block
causes a fault after reading both the pointer and its target. An integer
zero in the pointer slot causes a fault after reading that slot alone.
Both faults precede the store and leave the destination untouched.
An assertion that reads the old destination before the write puts it in
the key. The proof uses the next
step from the assertion visit to account for its reads. A write that
appears on a normal exit has succeeded, since an attempted store that
faults ends the execution. Every successful store overwrites a whole
block. The Safety, Reach and Exit correspondence excludes evaluations
of a marked holder. [Known difference](frame.md#reading-a-marked-holder).

For an OCaml hit, the overlay set is `W_exit`. Keep `W` in the
footprint to cover writes on all prefixes, including faulting and
nonterminating runs. [The parent spec][spec] describes calling `reuse`
with `W`. The entry result narrows that set to `W_exit`.
The [checked prefix case](#checked-cases) shows why. A precise producer
output may constrain a block written on a faulting branch to its old
value at a normal exit, where the matching execution keeps a different
old value. Composition with frame and lifetime replay remains open.

[spec]: https://github.com/nyandrianinamamy/frama-c/issues/32

**Declaration.** `ReuseModel.CacheEntry.sound_of_producer` in
[`lean/ReuseModel/Entry.lean`](../../../lean/ReuseModel/Entry.lean).

**Statement.**

```lean
@CacheEntry.sound_of_producer : ∀ {M : Type} {d : Domain M} [inst : Memory M] {entry : CacheEntry d}
  {a : AllocatorAgreement M},
  (∃ w, d.γ entry.input w) → entry.ProducerSound → entry.Coverage → entry.KeyCovers → entry.Sound a
```

**Hypotheses.**

1. `[Memory M]`. Proved in Lean for `FunMem`. See the
   [frame entry](frame.md#frame-lemma-with-lexical-sweeps).
2. `d : Domain M` and `entry : CacheEntry d`. Model parameters. The subject
   contains the fragment proof and the entry supplies the common initial
   bindings and stored parts. The construction uses the concretisation of
   the domain.
3. `a : AllocatorAgreement M`. Model parameter with laws proved in Lean
   for `FunMem.allocatorAgreement`. The relation is reflexive. It is
   preserved by paired stores of the same value to the same block, by
   paired releases and lexical sweeps of a block, and by paired creations
   of the same value.
   Paired creations also choose the same identifier. For `FunMem` the
   relation is equality of the next fresh identifier. Reflexivity makes
   every producing memory match its own entry, by `matches_of_input`.
4. `∃ w, d.γ entry.input w`. OCaml obligation. Non-emptiness is explicit
   in `Sound`, as in [Matching](matching.md#non-emptiness-of-the-stored-concretisation-stays-a-hypothesis).
5. `entry.ProducerSound`. Relied on from Eva. From each memory covered by
   the stored input, the producer covers each normal exit with its state for
   that outcome, records each possible alarm and never calls a failed
   assertion valid, and records each reached label. This is the ordinary
   soundness premise for the body analysis behind
   `Compute_functions.Make.compute_using_body` in
   `plugins/eva/src/engine/compute_functions.ml`. The model takes the
   premise as given.
6. `entry.Coverage`. OCaml obligation. For each producing memory, every
   prefix read is in `reads` and every prefix write in `writes`, including
   a read or write whose access faults. On a normal exit every write is
   in `exitWrites` and every member of `sureWrites` has a write in that
   execution. Labels, outcomes, alarms and assertion validity are covered
   by hypothesis 5. [Body access collector](body-access.md#whole-block-observations-and-exits)
   records the candidate sets `R`, `W`, `W_exit` and `W_sure`.
   Its [implementation](../../../plugins/eva/src/engine/body_access.ml)
   returns them through
   [`Body_access.Result.t`](../../../plugins/eva/src/engine/body_access.mli).
   Establishing these bounds for every producing memory of an admitted
   entry is open. The collector record leaves contract and annotation
   read coverage, child composition, and replay open.
7. `entry.KeyCovers`. OCaml obligation. The key contains `reads` and
   `exitWrites \ sureWrites`. Closing their union under `relate` can
   enlarge the key. The construction uses membership and the later
   projected match uses closure. The [entry producer](cache-producer.md#key-and-footprint-from-the-collector)
   establishes the inclusion and closure on the collected sets. The
   argument and regression are recorded there.

**Source evidence for R.** Each executed read hook adds its possible
bases with `Bases.join` in `Body_access.add_read`. The sure-write
accumulator is independent. A read reported after a sure write to the
same block therefore contributes to `R`. In `x = 1; return x;`,
`Transfer_stmt.return` assigns to the return slot. The cvalue
`extract_lval` hook records the read of `x` on the evaluation path,
and `copy_one_loc` records it on the direct copy path. This is source
evidence for the recorded read. Coverage of all model reads for an admitted
entry remains open.
[Return transfer](../../../plugins/eva/src/engine/transfer_stmt.ml),
[cvalue reads](../../../plugins/eva/src/domains/cvalue/cvalue_queries.ml),
[cvalue copies](../../../plugins/eva/src/domains/cvalue/cvalue_transfer.ml).

Inout's [`transfer_exp`](../../../plugins/inout/src/operational_inputs.ml)
subtracts the preceding sure writes from operational inputs, so the
read in that example can be absent. Also,
[`store_cacheable_call`](../../../plugins/eva/src/engine/mem_exec.ml)
drops fully overwritten bases from the output bases it adds to the
memexec key. Operational inputs and the existing memexec key thus do
not establish this footprint's read coverage.

The conclusion `entry.Sound a` quantifies over `entry.Matches a m`. A
match supplies `w` with `d.γ entry.input w` and
`ReplayAgreement a entry.key entry.footprint.writes w m`. The latter
contains these premises of execution correspondence:

| Premise | Kind | Status |
|---|---|---|
| Agreement on key contents with one stored witness | Proved in Lean under the matching hypotheses | [Matching](matching.md) gives the content witness |
| Equal liveness on the write targets for that witness and the current memory | OCaml obligation | Pending. Putting variable-validity targets in the key makes their liveness agree. Targets left out need another argument for the two memories. |
| Allocation agreement for the same witness and the current memory | OCaml obligation | Pending. The allocator laws are proved for `FunMem`; agreement of the witness under the chosen matching rule is a separate premise. |
| The same program, statement and entry bindings in the two executions | Model restriction | Fixed by the entry. Applicability to Eva calls is open. |

**Depends on.** [Finite-prefix correspondence](#finite-prefix-correspondence)
and the definitions of [observations](../../../lean/ReuseModel/Observations.lean).
[Matching](matching.md) gives key agreement only. Its `Combinable` mixes
contents, and the `FunMem.combinable` implementation may raise the next
identifier to the maximum of the two memories. Its exactness witness
therefore needs additional justification before it can supply the
allocation clause of `Matches`. In
[`projected_match_no_replay_witness`](#checked-cases), the current
memory has blocks 0 and 1 with next identifier 2. The projection on
`[0]` succeeds, but every stored witness has block 2 live and therefore
has a next identifier above 2. The allocator clause fails for any key
and write set in this example. Enlarging the key to
`R ∪ W_exit`, the parent spec's fallback, supplies no allocator agreement.

**Evidence.** Tree of `lean/` `a84123b158f292d1debae406ac75950ee89cb87a`
at commit `b1fa74dbca1ca91aff261a5f268583c35d6c740f`. The command
`cd lean && lake build --wfail` exited 0 on 2026-11-18 on a `git archive`
extraction with no build directory, using Lean 4.28.0, commit
`7e01a1bf5c70`. The checked statements and axiom reports are printed by
`lean/Checks/Axioms.lean`. CI: [run 44402277212](https://github.com/nyandrianinamamy/frama-c/actions/runs/44402277212) succeeded on this tree.

```
'ReuseModel.CacheEntry.sound_of_producer' depends on axioms: [propext, Quot.sound]
```

**Open.** For each current memory `m` covered by an admitted match,
the within-analysis hit proof must derive the following, with common
program, subject and entry bindings (both runs start with `entry.env`).

```lean
∃ w, d.γ entry.input w ∧ ReplayAgreement a entry.key entry.footprint.writes w m
```

The coverage obligations above and composition with frame and reuse
also remain open. Sub-block writes and the argument for offsets are
outside this model.

## A producing memory matches its own entry

**Kind.** Proved in Lean.

**Claim.** Reflexive allocation agreement lets a memory covered by the
stored input serve as its own matching witness. Together with the
non-emptiness premise of `sound_of_producer`, this ensures there is a
memory to which `Sound.matched` applies.

**Hypotheses and scope.** `[Memory M]`, the domain, entry and lawful
allocator agreement are model parameters as above. At this match, the
sole local premise is that the producing memory belongs to the stored
concretisation. The end-to-end hit obligation for a different current
memory is the one above.

**Statements.**

```lean
@AllocatorAgreement.refl : ∀ {M : Type} [inst : Memory M] (self : AllocatorAgreement M) (m : M), self.rel m m

FunMem.allocatorAgreement : AllocatorAgreement FunMem

@ReplayAgreement.refl : ∀ {M : Type} [inst : Memory M] (a : AllocatorAgreement M) (K W : BlockSet) (m : M),
  ReplayAgreement a K W m m

@CacheEntry.matches_of_input : ∀ {M : Type} {d : Domain M} [inst : Memory M] {entry : CacheEntry d}
  {a : AllocatorAgreement M} {m : M}, d.γ entry.input m → entry.Matches a m
```

**Evidence.** Same build as the construction.

```
'ReuseModel.AllocatorAgreement.refl' does not depend on any axioms
'ReuseModel.FunMem.allocatorAgreement' depends on axioms: [propext]
'ReuseModel.ReplayAgreement.refl' does not depend on any axioms
'ReuseModel.CacheEntry.matches_of_input' depends on axioms: [propext]
```

## Finite-prefix correspondence

**Kind.** Proved in Lean.

**Claim.** Given keyed reads, recorded writes and the initial
`ReplayAgreement`, the two runs at each finite step count have the same
events and control, including the outcome, bindings or fault where
applicable. Their contents agree on the key and on every block written,
created or released along the prefix, including the targets of lexical
sweeps. A sweep applies the same value transformation to any other block
already in agreement. Write attempts that fault also
establish equality of the cell contents, which are absent in both memories.
At an assertion visit, agreement on its reads gives equal truth values.

**Scope.** Whole blocks. The helper lemmas apply to the concrete step
function for any program. The entry theorem applies them to a subject of
the model fragment.

For a chosen producing prefix, `run_agree_on_writes` requires liveness
agreement only on the targets of its attempted stores. `writeTargets`
selects those events. Scope events and sweeps continue to use the allocator laws.
The entry construction still uses the static write bound `W` in
`Matches` to cover every prefix.

**Declarations.** `ReuseModel.run_agree`, `ReuseModel.run_agree_on_writes`
and `ReuseModel.assertionHolds_agree`, in
[`lean/ReuseModel/Replay.lean`](../../../lean/ReuseModel/Replay.lean).

**Statements.**

```lean
@run_agree : ∀ {M : Type} [inst : Memory M] {a : AllocatorAgreement M} {K W : BlockSet} {p : Program} {c : Config M}
  {m : M},
  ReplayAgreement a K W c.mem m →
    (∀ (evs : List Event) (c' : Config M), Steps p c evs c' → AccessesCovered K W evs) →
      ∀ (fuel : Nat),
        match run p fuel c with
        | (evs, c') =>
          ∃ m', run p fuel (c.withMem m) = (evs, c'.withMem m') ∧ ReplayAgreement a (updatedBlocks evs ++ K) W c'.mem m'

writeTargets : List Event → BlockSet

@run_agree_on_writes : ∀ {M : Type} [inst : Memory M] {a : AllocatorAgreement M} {K : BlockSet} {p : Program}
  {c : Config M} {m : M} (fuel : Nat),
  ReplayAgreement a K (writeTargets (run p fuel c).fst) c.mem m →
    (∀ (b : Block), Event.read b ∈ (run p fuel c).fst → b ∈ K) →
      match run p fuel c with
      | (evs, c') =>
        ∃ m',
          run p fuel (c.withMem m) = (evs, c'.withMem m') ∧
            ReplayAgreement a (updatedBlocks evs ++ K) (writeTargets evs) c'.mem m'

@assertionHolds_agree : ∀ {M : Type} [inst : Memory M] {p : Program} {env : Env} {m n : M} {e : Expr} {K W : BlockSet},
  AgreeOn K m n → AccessesCovered K W (evalExpr p env m e).fst → assertionHolds p env n e = assertionHolds p env m e
```

**Hypotheses.** The theorems use `[Memory M]` (proved in Lean for
`FunMem`). The program, block lists, configurations, expression and
memories are model parameters. In `run_agree`, `a` supplies the
allocation laws, and the initial `ReplayAgreement` is a local premise
supplied by the entry match. Coverage of every producing prefix is a local
premise given by `Coverage` and `KeyCovers` in entry construction.
The step count selects the prefix. In `run_agree_on_writes`, the
local coverage premise is that this prefix's reads belong to the key.
The initial `ReplayAgreement` uses the store targets of that prefix as
its liveness set and retains allocator agreement. In
`assertionHolds_agree`, `AgreeOn K m n` and the coverage of the
expression's events are local premises established at the paired
assertion visit. The selected
environment is common to both evaluations.

**Depends on.** The laws of `Memory` and the definitions of the
[semantics](../../../lean/ReuseModel/Semantics.lean).

**Evidence.** Same build as the [construction](#sound-entry-from-producer-soundness-and-coverage).
The [sweep and Inner build](frame.md#frame-lemma-with-lexical-sweeps)
rechecks these statements and their axiom output with lexical scopes.


```
'ReuseModel.run_agree' depends on axioms: [propext, Quot.sound]
'ReuseModel.writeTargets' depends on axioms: [propext]
'ReuseModel.run_agree_on_writes' depends on axioms: [propext, Quot.sound]
'ReuseModel.assertionHolds_agree' depends on axioms: [propext]
```

**Open.** Allocation agreement and write validity for the actual
matching witness are open in Eva, as listed under the construction.

## Checked cases

**Kind.** Proved in Lean.

**Claim and scope.** The following closed statements exercise the
construction, coverage rejection, and limits of key agreement in the
whole-block model. Blocks `0`, `1` and `2` are `x`, `p` and the target
of `p` in the pointer load and assertion fixtures.

| Declaration | Checked behavior |
|---|---|
| `Checks.load_overwrite_entry` | Applies `sound_of_producer` with key `[1, 2]`. With a dead target the load faults before the write, the destination remains 9, and the entry covers the alarm and visit. With a live target the entry covers a normal exit and agrees on the new value 7 of the omitted destination. |
| `Checks.assert_before_overwrite` | With reached labels 1, 2 and 3, producer soundness and coverage hold. The construction makes key `[0, 1, 2]` sound and a producing memory matches itself. Key `[1, 2]` fails `KeyCovers`. The assertion holds at the visit with old value 0 and fails at the visit with old value 9 even though the latter run completes and overwrites `x`. |
| `Checks.missing_pointee_rejected` | The producer for `return *p` covers return value 7 from its input and fails coverage when its footprint records block 1 only. |
| `Checks.projected_match_no_replay_witness` | The filtered states agree on `[0]` and there is a content witness. The current allocator is incompatible with every stored witness, regardless of the liveness set or key. |
| `Checks.dead_destination_no_match` | The keyed contents agree, but the dead destination faults at the write. No stored witness agrees on its liveness. |
| `Checks.nonpointer_load_reads_only_pointer` | An integer zero in the pointer slot causes a fault with a single read of block 1. |
| `Checks.allocator_needed` | With the same key contents, a nested call can return different pointers. The fresh identifiers are 2 and 3. |
| `Checks.prefix_writes_can_exceed_exit_writes` | The taken branch for `p = 1` writes `x` and has no normal exit. The normal exits for `p = 0` preserve the distinct initial values of `x` in the two memories. The producing exit cannot supply the current value on this footprint write. |

**Declarations and statements.** The declarations are in
[`lean/Checks/Entries.lean`](../../../lean/Checks/Entries.lean).

```lean
load_overwrite_entry : assignEntry.key = [1, 2] ∧
  ¬0 ∈ assignEntry.key ∧
    Prefix assignSubject { env := noLocals, mem := loadInput 9 false } loadReads
        (Config.fault 1 Alarm.invalidAccess (loadInput 9 false)) ∧
      assignEntry.violations (Violation.alarm 1 Alarm.invalidAccess) ∧
        assignEntry.reached 1 ∧ ∃ w, predicates.γ (assignEntry.exit Outcome.completed) w ∧ AgreeOn [0] w (loadOut 9)

assert_before_overwrite : assertEntry.key = [0, 1, 2] ∧
  assertEntry.ProducerSound ∧
    assertEntry.Coverage ∧
      assertEntry.KeyCovers ∧
        assertEntry.Sound FunMem.allocatorAgreement ∧
          assertEntry.Matches FunMem.allocatorAgreement (loadInput 0 true) ∧
            0 ∈ assertEntry.key ∧
              ¬assertEntryWithoutX.KeyCovers ∧
                AgreeOn [1, 2] (loadInput 0 true) (loadInput 9 true) ∧
                  assertionOf? loadProg
                        (run loadProg 1 (Config.entry testFirst { env := noLocals, mem := loadInput 0 true })).snd =
                      some (2, true) ∧
                    AssertionFails assertSubject { env := noLocals, mem := loadInput 9 true } 2 ∧
                      Exit assertSubject { env := noLocals, mem := loadInput 9 true } Outcome.completed (loadOut 9)

missing_pointee_rejected : missingPointee.ProducerSound ∧
  Exit returnSubject { env := noLocals, mem := returnIn } returnOutcome returnIn ∧ ¬missingPointee.Coverage

shorterInput : FunMem

projected_match_no_replay_witness : valueProd.filter [0] matchC = valueProd.filter [0] matchS ∧
  valueProd.γ matchC shorterInput ∧
    (∃ w, valueProd.γ matchS w ∧ AgreeOn [0] shorterInput w) ∧
      ∀ (K W : BlockSet), ¬∃ w, valueProd.γ matchS w ∧ ReplayAgreement FunMem.allocatorAgreement K W w shorterInput

deadDestination : FunMem

dead_destination_no_match : AgreeOn [1, 2] (loadInput 0 true) deadDestination ∧
  ¬assignEntry.Matches FunMem.allocatorAgreement deadDestination ∧
    AlarmRaised assignSubject { env := noLocals, mem := deadDestination } 1 Alarm.invalidAccess

nonpointer_load_reads_only_pointer : Prefix assignSubject { env := noLocals, mem := memOf [Value.int 9, Value.int 0] }
  [Event.read 1] (Config.fault 1 Alarm.invalidAccess (memOf [Value.int 9, Value.int 0]))

allocator_needed : AgreeOn [0, 1] leakState.mem laterLeakState.mem ∧
  ¬FunMem.allocatorAgreement.rel leakState.mem laterLeakState.mem ∧
    Memory.load (run leakProg 7 (Config.entry leakStmt leakState)).snd.mem 0 = some (Value.ptr 2) ∧
      Memory.load (run leakProg 7 (Config.entry leakStmt laterLeakState)).snd.mem 0 = some (Value.ptr 3)

prefix_writes_can_exceed_exit_writes : Event.write 0 ∈
    (run loadProg 6 (Config.entry faultOnlyWrite (faultOnlyInput 3 1))).fst ∧
  AgreeOn [1] (faultOnlyInput 3 0).mem (faultOnlyInput 9 0).mem ∧
    Exit faultOnlySubject (faultOnlyInput 3 0) Outcome.completed (faultOnlyInput 3 0).mem ∧
      Exit faultOnlySubject (faultOnlyInput 9 0) Outcome.completed (faultOnlyInput 9 0).mem ∧
        (∀ (o : Outcome) (out : FunMem), Exit faultOnlySubject (faultOnlyInput 3 1) o out → False) ∧
          ∀ (o : Outcome) (out : FunMem),
            Exit faultOnlySubject (faultOnlyInput 3 0) o out → ¬AgreeOn [0] out (faultOnlyInput 9 0).mem
```

**Hypotheses.** None. The cases are closed statements.

**Depends on.** [Sound entry from producer soundness and coverage](#sound-entry-from-producer-soundness-and-coverage),
the concrete semantics, and the observation helpers in
[`lean/Checks/Examples.lean`](../../../lean/Checks/Examples.lean).

**Evidence.** Same build as the construction.

```
'Checks.load_overwrite_entry' depends on axioms: [propext, Quot.sound]
'Checks.assert_before_overwrite' depends on axioms: [propext, Quot.sound]
'Checks.missing_pointee_rejected' depends on axioms: [propext, Quot.sound]
'Checks.shorterInput' depends on axioms: [propext]
'Checks.projected_match_no_replay_witness' depends on axioms: [propext, Quot.sound]
'Checks.deadDestination' depends on axioms: [propext]
'Checks.dead_destination_no_match' depends on axioms: [propext, Quot.sound]
'Checks.nonpointer_load_reads_only_pointer' depends on axioms: [propext]
'Checks.allocator_needed' depends on axioms: [propext]
'Checks.prefix_writes_can_exceed_exit_writes' depends on axioms: [propext, Quot.sound]
```

**Open.** The fixtures exercise the model. Regressions for the real
collector and matching rule remain open.
