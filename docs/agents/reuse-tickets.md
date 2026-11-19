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
- **One test per check, removed alone.** Each check, at storage and at
  lookup, has a test that fails when that check alone is removed. A test
  where another check rejects the candidate first does not count: assert
  the exact reason and which candidate is examined next.
- **A hit skips visits.** The statements of a body answered by a hit have
  no saved state and no visit, for the body and for every function it
  called. Before admitting a hit, list who reads them afterwards: the
  passes at the end of the analysis, `-then` options, server requests, a
  plug-in loaded later, a saved session. Each reader gets a delivery, a
  refusal or a line in the record, with a test compared against caching
  disabled.
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
- **A change of behaviour makes sentences stale outside the entry of the
  ticket.** After a fix or a rebase, search the whole record for what it
  said of the old behaviour, and check each sentence handed to a later
  ticket against a committed check, as any other claim.
- **Lean first, then the record.** Make the Lean commits, then the record
  commits that cite `git rev-parse HEAD:lean`. A rebase keeps the tree and
  changes the commit beside it: `bash dev/check-record.sh` finds a cited
  commit that is no longer in the history.
- **The default ptests need the network once.** The SARIF test of
  `markdown-report` downloads its schema. A failure of `ptests-default` on
  that download alone is a sandbox limit: rerun the step with network access
  and report both runs.
- **To see why a cram command fails**, copy the fixture directory to a
  scratch directory and run the command there through
  `dune exec -- sh -c '...'` from the checkout: the sandbox of the test
  keeps the redirected log out of reach.
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
   Mutate it: weaken each predicate or law in a scratch copy and check that
   a committed check stops compiling or a test fails. A check built from
   constant functions rarely does.
4. **Compare each record claim with its statement.** Printed statements and
   axiom lines match `#check` and `#print axioms`; a claim does not exceed
   them; results of a ticket that has not landed are cited as pending.
5. **Check the oracles.** List the existing expectation files that changed
   and confirm each added line is what the ticket adds.
6. **Say what the fixtures cannot see.** Name the acceptance criteria whose
   test would pass with a wrong implementation.

7. **Leave the analysis of one body.** For a state the change keeps
   outside the project states, or a hook with one slot: try the other
   callers of a public kernel function, a session saved and loaded in
   another process, a second project, and another client of the hook.

8. **Read the results after a hit.** With a confirmed hit, run the
   readers of the skipped body (end-of-analysis statuses and dead code,
   `-then` printers, a server request, a session loaded in another
   process) and compare with caching disabled.

Report findings by severity with file, line, a failing input and a proposed
fix, and state for each acceptance criterion whether it is met. The
implementer's table of criteria is in its final report and reaches the
ticket at closing: when the commits hold none, judge the criteria from the
replay, not from the absence of the table.

## Landing

One ticket at a time, on the integration branch, with linear history: rebase
the ticket branch onto the tip, run `bash dev/verify.sh` (or
`cd lean && lake build --wfail` for a Lean ticket) on the rebased commit,
fast-forward, push, and cite the CI run of that push. A push to the branch
cancels a CI run still in progress on it: wait for the run that is the
evidence of the previous ticket.

A fix written after the last review in the kernel, the collector or a Lean
statement gets a narrow re-check of those commits before the ticket closes;
every re-check of this kind so far found a defect or a wrong record
sentence. A rebase that resolves a conflict in those files counts as such
a fix: rerun the regressions of both tickets and list what was reconciled.
Fixes to prose, expectations or fixtures alone do not need one.

`git commit` and `git push` run the hooks, which need the activation lines
of [AGENTS.md](../../AGENTS.md) in the same shell. In a script that waits
for other builds, do not test `pgrep -f` with a pattern that the script's
own command line contains: it waits on itself.
