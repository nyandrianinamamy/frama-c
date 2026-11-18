# Correspondence record for reuse in Eva

This record relates the claims made about the reuse of cache entries in Eva
to their evidence: theorems of the Lean model, arguments in prose, and
obligations on the OCaml code of Eva with the regressions that exercise them.
Its form is fixed by the
[resolution of issue #19](https://github.com/nyandrianinamamy/frama-c/issues/19),
and the review rule is in the root `AGENTS.md`, under "Reviewing Lean–Eva
correspondence". Terms are those of `GLOSSARY.md`.

Each topic file below holds one entry per claim, under its own heading, so
that a claim can be linked. An entry gives the claim and its scope, its kind,
its dependencies, its evidence and the checks still open. The kinds are:

- **Proved in Lean**: the declaration, its statement and hypotheses, the
  checked revision and the `#print axioms` output, with any custom axiom or
  `sorryAx` flagged.
- **Argued in prose**: the reasoning, its premises, and pointers that let a
  reviewer check each step.
- **OCaml obligation**: the Eva symbols responsible, why their paths establish
  the claim, and the regression that exercises it. Source inspection is kept
  apart from execution, and checks still pending are listed.
- **Relied on from Eva**: the contract cited, the claim that depends on it,
  and whether its implementation has been checked.
- **Known difference**: the difference, the claim that the model covers, and
  the evidence needed to extend the coverage.

A topic file holds the current argument. The test suite holds the runnable
cases. The results for a checked revision are recorded by the change or the
CI run that produced them.

## Topics

- [Call-cache seam](call-cache-seam.md): the seam through which memexec
  answers calls, the dispositions of each call, their reasons and their
  counts, and the closure of the memexec key under `relate`.
