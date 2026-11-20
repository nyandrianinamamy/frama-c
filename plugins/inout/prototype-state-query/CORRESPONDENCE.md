# Correspondence record: claims affected by the migration of the readers

The Lean–Eva correspondence record is kept outside this branch, in
`docs/eva/reuse-correspondence/` of the branch
`spec/32-reuse-within-analysis`. This file was checked against:

- record revision `9d5d1c90ef8b0eef379c517533ee75fc7aa61192`;
- Lean tree `cbb602472b8e2f73ea1560c4f265039aea5e44c9`
  (`git rev-parse spec/32-reuse-within-analysis:lean`).

This change modifies neither that branch nor `lean/`, and this branch has
no `lean/` directory. The Lean build was not run: no claim of kind "proved
in Lean" is affected.

## Scope

The record describes the reuse within one analysis that `spec/32`
implements (`Cache_part`, `Reach_delivery`, `Safety_delivery`, supplied
entries). This branch forks from `3988ef5bd8`, before that implementation,
and contains none of it. On `spec/32`, the claims are unchanged. The
migration of the readers (#74 to #80) changes the Eva code that some of
these claims cite: readers and writers now consult the hit log before the
legacy result store. Each section below names one claim of the record, the
cited symbols, the symbols now responsible on this branch, whether the
argument still holds when the two branches are combined, the evidence on
this branch, and the obligations that remain open.

The record itself is updated when the two branches are combined: the
claims marked "open" need their argument changed then. Until then, this
file holds the assessment.

The search: every claim whose text cites `register_state`,
`record_fireable`, `add_condition`, `register_caller`,
`register_analysis_target`, `Engine.find`, `Engine.Make.find`,
`Engine.callstacks`, `Analysis.status`, `are_available`, `Self.is_computed`,
`ComputationState`, `analysis_status` or `is_computed`, in every file of
the record. Two matches cite only `Cache_part.register_state_reader`
([Readers of the states saved at statements reject every
candidate](#unaffected-matches), [A hit runs no client that is not
audited](#unaffected-matches)) and are unaffected.

## Evidence on this branch

One command runs the acceptance driver and its controls:

```sh
bash plugins/inout/prototype-state-query/acceptance.sh
```

The controls cited below are those of its report (`report.md`); the cram
tests are under `plugins/eva/tests/utils/`. `RESULTS.md` records the
revision and results of the last run.

## cache-parts.md: The kept part covers the skipped computation

**Cited.** Premise 2: the results of Eva are unavailable while the analysis
runs, since `Engine.find` answers `Top` at every point while
`Self.is_computed` does not hold; `Eva.Results.is_reachable` then holds for
every statement, the state at the start of a call (`at_start_of`, the
`Pre` label of InOut) is `Top`, and the `Init` label reads the initial
state (`Eval_terms.add_init`), the same for every call.

**Now.** While the hit log records, these requests are served by the hit
log, before `Engine.find`: the classification of every point is
`Unavailable Pending` (`Top`), `Results.is_reachable` answers true,
`Eva.Analysis.is_computed` answers false, and `Eva.Analysis.status`
answers `Analyzed Partial` for an analyzed function. InOut takes `Top` as
its `Pre` state without a request. The `Init` label reads
`Hit_log.initial_state`, recorded once per analysis. The records are
started before the computation state becomes `Computing`, and sealed or
interrupted before it becomes `Computed` or `Aborted`, so that the hooks on
these changes see the same availability on both paths.

**Holds.** Yes: the answers during the analysis are those of the legacy
path, the same for every call.

**Evidence.** `reach-availability.t`, "Pending results": during the
analysis, the candidate, under the trap of every read, answers reachable,
`Top`, no callstack, status partial and no result available, as the
reference; the only difference, `is_empty`, is documented there.
`legacy-read-guard.t`: `trap:collection` with the hit log is not trapped.
Acceptance controls `inout-collection` and `inout-memexec-parity`.

**Open.** From is not loaded in the minimal configuration: its
`is_reachable` requests take the same path, but no test runs them. An
analysis started by a callback during the analysis replaces the records
(`Hit_log.start`); it is not exercised.

## cache-parts.md: Results computed from statement states are refused after a hit

**Cited.** Item 2, "The refusal in the engine": every query of
`Eva.Results` at a statement or at the start of a function goes through
`get_state` and `get_state_by_callstack`, defined by `Engine.Make.find`,
and `Engine.Make.Engine.callstacks`; `find` and `callstacks` call
`Safety_delivery.check_readers`. The stores are read without the engine in
three places: `Eva_results` (row 12), `Eval_terms` (row 13) and the printer
of the final values (row 3).

**Now.** The queries of `Eva.Results` ask the hit log first
(`Hit_log.reach`, `select`, `classify`, through `Results`) and reach
`Engine.find` only when it declines. The engine's `callstacks` is removed:
it had no caller. The three direct readers ask the hit log first:
`Eva_results.get_results` (`Hit_log.stored_states`, `Hit_log.calls`, and
the records themselves in the snapshot), the `Init` label
(`Hit_log.initial_state`) and the printer (`Cvalue_reads`, installed by
the hit log). In the table of rows, the source pointers change: row 1
(`engine.ml:68`, `:73`) to the resolver of `Hit_log`; row 3
(`cvalue_domain.ml:459`) to `Cvalue_reads`; rows 5 and 6 (`Eval_annots`,
`Summary`) to `Results.is_reachable` and `Hit_log.analyzed`; row 12
(`eva_results.ml:145`, `:190`) to the snapshot of the records; row 13
(`engine.ml:170`) to `Hit_log.initial_state`.

**Holds.** No, for a combination: a query that the hit log serves does not
reach `check_readers`.

**Open.** The combination must refuse on the hit-log path too, or have the
hit log decline after a hit of a supplied entry, so that the query reaches
`Engine.find`. The hit log already declines after a memexec hit
(`has_hit`); a hit of a supplied entry is not one of its invocation kinds.

## reach.md: The queries see the points reached by a hit, with the state top

**Cited.** The queries of `Results` read the states through
`Engine.get_state`, `get_state_by_callstack` and `callstacks`, which read
the store of `Engine.Make_Domain`, where `Points` answers `Top`;
`Eva_results.get_results` and `set_results` carry the records of the hits.

**Now.** The hit log serves the queries; it declines at the points of a
memexec hit and on the stacks below one, and the query then reads the
store. `get_results` and `set_results` also carry the records of the hit
log.

**Holds.** Only if the hit log declines at the points of a hit of a
supplied entry. Otherwise it classifies these points from the recorded
visits: no visit of the body reaches them, so it would answer `Bottom`
where the claim requires `Top`.

**Evidence.** For memexec hits, which the hit log records: `stack-selection.t`
and `hit-log-resolver.t` show the requests at the points of a hit reading
the store (record mode). `snapshot-round-trip`: the restored records answer
the statuses read before the export.

**Open.** Record a hit of a supplied entry in the hit log as a hit, so that
it declines its points, the stacks below it, the call relations and the
guard outcomes; carry both sets of records in a snapshot.

## reach.md: The Reach part records the reach of the body

**Cited.** Each table has one writer during an analysis, and each writer
records its write before it changes the table: the states
(`Engine.Make_Domain.Store.register_state`), the guard outcomes
(`Iterator.add_condition`, called by `record_fireable`; "`Conditions_table`
has no other writer"), the call sites (`Function_calls.register_caller`,
called by `register_analysis_target`).

**Now.** While the hit log records, `register_analysis_target` writes the
callers and status tables from `Hit_log.target`, without the merge of
`register_call`, the counterpart of `register_caller` here;
`record_fireable` writes `Conditions_table` from `Hit_log.fire`, without
`fire`, the counterpart of `add_condition`. `register_state` writes the
store itself, with the state already registered taken from
`Hit_log.registered`. Otherwise, the writers read the tables as before.

**Holds.** The values written are those of the legacy path. The recording
points of `spec/32` (`Reach_part.record_caller`, `record_guard`) sit in
`register_caller` and `add_condition`, which the hit-log branch skips: a
combination must record on both branches, or the Reach part misses call
sites and guard outcomes.

**Evidence.** `legacy-store-writes`: on every fixture, with the hit log
declining every request, the requests read the tables written from the
records and give the reference's answers. `hit-log-registration`: the
three writers resolve from the hit log during the analysis of every
candidate. Default Eva ptests.

**Open.** The recording points on the hit-log branch, for the combination.

## hit.md: Side-table obligations for skipped work; body-access.md: Side tables and recorded joins

**Cited.** `Iterator.record_fireable`, `Function_calls.register_caller` and
`Engine.Store.register_state` among the writers whose joins a hit replays
(`RecordedWrite`).

**Now.** As above, while the hit log records, these writers merge with the
facts of the records, then replace the entry of the table.

**Holds.** Not for a combination as it stands: a hit that replays its
writes into the tables directly is not in the records, and a later
registration on the hit-log branch replaces the table entry with a merge
that omits the replayed facts.

**Open.** A combination must either replay through the records or stop
the hit log from recording once a hit replays (the writers then read the
tables). No supplied-entry hit exists on this branch.

## inner.md: Saved states and the public query; cache-producer.md: Provenance, storage and lookup

**Cited.** `Engine.Store.register_state` joins the registrations for the
same control point and callstack.

**Now.** It still joins them. While the hit log records, the earlier
registrations come from the records: the inputs of the visits on the
callstack, at the start of a function; the states of the earlier body
visits on the callstack, at a statement.

**Holds.** Yes on this branch: the records hold every visit that registers
a state. For a combination, the obligation of the previous section
applies.

**Evidence.** `legacy-store-writes` and `native-equality` on `loop.c` and
`selection.c`, whose loops visit a function twice on one callstack.

## safety.md: The passes after the analysis draw no conclusion where the queries do not see the points of a hit

**Cited.** `Results.is_reachable`, `Eval_annots.mark_unreachable` and
`Cvalue_domain.State.Store.is_computed`.

**Now.** The passes ask the hit log (`Results.is_reachable`,
`Hit_log.analyzed`).

**Holds.** As for the queries (above): only if the hit log declines at the
points of a hit of a supplied entry.

**Evidence.** Under the continuous trap, every candidate reads nothing in
the post-analysis phase (`scope` records, `guard-sensitivity`), while the
same battery on the legacy path reads there; `trap:post-analysis` traps
`Eval_annots.mark_unreachable` on the legacy path.

**Open.** The same as for the queries.

## reuse-operation.md: A supplied entry is used only where a hit is supported

**Cited.** `Self.ComputationState`: the analysis sets `Computing` after its
start hooks, and an analysis started by a callback sets `Computed` or
`Aborted` when it ends.

**Now.** `Hit_log.start` runs before `Computing`; `seal` and `interrupt`
run before `Computed` and `Aborted`. A nested analysis starts new records.

**Holds.** The computation state changes as cited.

**Open.** A nested analysis, which replaces the records of the outer one,
is not exercised on this branch.

## Unaffected matches

- cache-parts.md, "Readers of the states saved at statements reject every
  candidate", and safety.md, "A hit runs no client that is not audited":
  the match is `Cache_part.register_state_reader`, not a symbol of this
  migration.
