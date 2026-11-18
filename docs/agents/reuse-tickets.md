# Working a ticket of the summary-reuse effort

For an implementer or a reviewer of a ticket under the spec
[reuse of cache entries within one analysis](https://github.com/nyandrianinamamy/frama-c/issues/32).
[AGENTS.md](../../AGENTS.md) gives the build, test and reporting rules; this
file adds what is specific to these tickets.

## Before designing

- The ticket text is the agreed design. Read it, the spec, and the design
  comments they link, with `gh issue view N --comments`.
- Read every ticket this one is blocked by. A closed ticket has a section
  "What was done" in its body and a comment "Decision log": the places where
  the delivered work differs from its text. Those decisions bind later
  tickets.
- Read the entries of the
  [correspondence record](../eva/reuse-correspondence/README.md) that concern
  the ticket.

## Implementing

- **Prefer a named refusal to an unproved support.** Before calling a case
  supported, look for what the evaluator, the transfer functions, the domain
  or a kernel table does behind it: a binding narrowed by a condition, a
  binding installed at scope entry, a table of the kernel read by pointer
  arithmetic. Each supported case needs a regression that fails without the
  change; each refusal reason a regression that reaches it.
- **A fixture entry must be one a producer could build.** Its key contains
  its read set, its producer input binds every block its exit keeps, and its
  exit sets are nested.
- **No side effect when the plug-in loads.** A variable or a table entry
  created at module initialisation shifts identifiers in the oracles of
  other plug-ins.
- **Record claims no broader than their support.** Each claim has a kind,
  its evidence with source inspection and execution told apart, and its open
  items. A claim about a class needs an argument for the class, not one
  example. Every premise of a printed statement has a kind, local premises
  included.
- **Lean first, then the record.** Make the Lean commits, then the record
  commits that cite `git rev-parse HEAD:lean`. A rebase keeps the tree and
  changes the commit beside it: `bash dev/check-record.sh` finds a cited
  commit that is no longer in the history.
- **The default ptests need the network once.** The SARIF test of
  `markdown-report` downloads its schema. A failure of `ptests-default` on
  that download alone is a sandbox limit: rerun the step with network access
  and report both runs.
- If the ticket cannot be met as written, build the closest sound version
  and report the divergence. Do not change the design silently.

## Reviewing

A review covers the diff against the ticket and against the standards.
These checks found defects in earlier tickets and are owed on each one:

1. **Find an unreported effect.** Build a program where the result is
   favourable (would be stored, hit, sound entry) and a state change, a read
   or a table access behind it is not reported. Run it; give the program.
2. **Run the negative control.** For each regression that carries a
   criterion, check that it fails when the fix is reverted.
3. **Check that no definition is vacuous.** A law that an empty relation or
   a one-state domain meets proves nothing about the cases of interest.
4. **Compare each record claim with its statement.** Printed statements and
   axiom lines match `#check` and `#print axioms`; a claim does not exceed
   them; results of a ticket that has not landed are cited as pending.
5. **Check the oracles.** List the existing expectation files that changed
   and confirm each added line is what the ticket adds.
6. **Say what the fixtures cannot see.** Name the acceptance criteria whose
   test would pass with a wrong implementation.

Report findings by severity with file, line, a failing input and a proposed
fix, and state for each acceptance criterion whether it is met.

## Landing

One ticket at a time, on the integration branch, with linear history: rebase
the ticket branch onto the tip, run `bash dev/verify.sh` (or
`cd lean && lake build --wfail` for a Lean ticket) on the rebased commit,
fast-forward, push, and cite the CI run of that push. A push to the branch
cancels a CI run still in progress on it: wait for the run that is the
evidence of the previous ticket.
