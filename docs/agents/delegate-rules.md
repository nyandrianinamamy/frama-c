# Rules for delegated work

Read this when you work on a ticket of this repository as a delegate: a
subagent or a child thread started by an orchestrating agent. The brief
gives what is specific to the ticket; these rules hold for every brief.

## Environment

- Activate the switch in every shell that builds, tests or commits, and use
  eight jobs: [AGENTS.md](../../AGENTS.md#build-and-prerequisites). In a
  worktree, the switch is that of the main checkout.
- Disk: see [setup.md](setup.md#disk-space). Put scratch outputs in
  `/dev/shm` when they fit, and remove the build trees and worktrees you made
  once your report is written.
- After a mutant run of `dev/cram-fresh.sh`, `_build` holds the last mutant:
  run `dune build -j 8 @install` before a `dune exec` probe.

## Writes

- Commit on the branch the brief names. The orchestrator pushes, opens pull
  requests, and edits issues; put what an issue should say in your report.
- Stage with explicit paths (`git add PATH...`). `docs/handoffs/` and
  `plugins/inout/prototype-state-query/` are local files, kept out of git by
  `.git/info/exclude`.
- Promote each reviewed oracle by its path, `dune promote PATH`, as in
  [AGENTS.md](../../AGENTS.md#test-configurations-and-oracle-investigation).
- Text meant for the issue tracker cites public sources only: this
  repository, upstream Frama-C, published papers.

## Scope

- Analyses without memexec (`-eva-no-memexec`, and the reference of
  `plugins/eva/tests/hit_log/hit_log_observer.ml`) run on the test programs
  of Eva only. Case studies such as gzip and monocypher run with memexec;
  the observer refuses them. Read the case studies in
  `~/Project/open-source-case-studies` without writing there.
- A limit that shows only under a non-default option, such as
  `-eva-no-results-function`, goes into the ticket's specification as a
  limit; it is outside the fix.
- The known issues are listed in issue #97. A difference that one of them
  explains is reported under its number, as known.
- Read issues with `gh issue view N --json number,title,body,labels,comments`
  ([issue-tracker.md](issue-tracker.md)).

## Report

Follow the definition of done in
[AGENTS.md](../../AGENTS.md#definition-of-done): the revision checked, the
exact commands with their exit status, `PASS`, `FAIL` or `NOT RUN` per
acceptance criterion, and the checks skipped with the reason.
