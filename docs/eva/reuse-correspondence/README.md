# Correspondence between the Lean model and Eva

This record relates the Lean reference model in [`lean/`](../../../lean/README.md)
to Eva's OCaml implementation of statement reuse. Each claim has one home, under
its own heading in one of the topic files listed below, so that it can be
linked.

A theorem of the model holds for the model. Whether Eva meets its hypotheses is
a separate claim, with its own evidence in this record. An entry of kind "proved
in Lean" says nothing about the OCaml code.

## Entries

Each entry states the claim and its scope, its kind, the claims it depends on,
its evidence and any open obligation. The kinds, and the evidence each one
needs:

- **Proved in Lean.** The declaration, its statement and hypotheses, the tree of
  `lean/` that was checked and the `#print axioms` output. Any custom axiom or `sorryAx` is
  flagged.
- **Argued in prose.** The reasoning, its premises, and pointers that let a
  reviewer check each step.
- **OCaml obligation.** The Eva symbols responsible, why the relevant paths
  establish the claim, and the regression that exercises it. Source inspection
  and execution are told apart, and checks still pending are listed.
- **Relied on from Eva.** The contract cited, the reuse claim that depends on
  it, and whether the implementation of that contract has been checked.
- **Known difference.** The difference, the claim that the model covers, and
  the evidence needed to extend coverage.

A topic file holds the current argument. The test suite holds the runnable
cases. A pull request or a CI run records the results at the checked revision.
On a change to the model or to Eva, follow the review rule in
[`AGENTS.md`](../../../AGENTS.md#reviewing-leaneva-correspondence).

## Replaying an entry proved in Lean

From the root of a checkout of the checked revision:

```sh
cd lean && lake build --wfail
```

The build prints the axioms of each theorem named in
`lean/Checks/Axioms.lean`. It fails if one of them depends on `sorryAx` or on an
axiom other than `propext`, `Classical.choice` and `Quot.sound`.

An entry identifies the checked model sources by the tree of `lean/`, the
output of `git rev-parse HEAD:lean`. The tree is the citation of record: it
stays the same when the history is rewritten or when a later commit changes no
file of the model. A commit may be cited beside it for convenience. To check
that a checkout has the model sources of an entry, compare
`git rev-parse HEAD:lean` with the tree given in the entry.

## Topic files

- [Frame](frame.md): the blocks that a statement does not access.
- [Domain laws](domain-laws.md): the laws of `filter`, `relate` and `reuse`,
  and the law that they depend on the members of a set of blocks only; the
  product of two domains; and the equality domain, with an identity
  `filter`, on the fact `y == z` as the negative case of the projected
  match.
- [Matching](matching.md): the match and product lemmas, closure of the key
  in the stored input, and the non-emptiness of the stored concretisation.
- [Entry construction](entry.md): producer soundness, coverage, the matching
  key, and the Exit, Safety and Reach claims.
- [Call-cache seam](call-cache-seam.md): the seam through which memexec
  answers calls, the dispositions of each call, their reasons and their
  counts, and the closure of the memexec key under `relate`.
- [Body access collector](body-access.md) covers the block sets, the reads
  and designations of ACSL clauses, the observational storage verdict and
  side-table classes.
- [Entries from fresh bodies](cache-producer.md) covers production, the
  key and footprint, and the producer obligations for supplying an entry.
- [Reuse operation](reuse-operation.md): the cache entry and its four
  written sets, the match by equality on entries supplied by a test module,
  the blocks a hit takes from an exit state, the choice of one cache per
  analysis, and the laws of `filter`, `relate` and `reuse` for cvalue.
