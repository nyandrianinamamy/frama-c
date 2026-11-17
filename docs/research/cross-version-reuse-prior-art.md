# How other static analyzers reuse results across program versions

Research note for issue #6. Sources were read on 2026-11-17. Every claim
carries a URL to a paper, official documentation or public source code, or a
path in this repository. Where a source could not be opened or a point is not
documented, the note says so.

## Answer

Nine published systems reuse analysis results across program versions: Goblint,
DAIG and its demanded-summarization successor, Infer, IncA/Laddder, CiaoPP,
Boogie/Dafny, Reviser, MAF, and an Eva prototype published at ECOOP 2025.
CPAchecker reuses precisions, not results.

- The unit of reuse is either a solver unknown or graph cell (Goblint, DAIG,
  IncA, CiaoPP, Reviser, MAF) or a per-procedure summary (Infer, Boogie, the
  Eva prototype, demanded summarization).
- The systems that match two separately parsed versions look a function up by
  its name and then compare bodies structurally (Goblint, Infer, the Eva
  prototype, Frama-C's `-ast-diff`). DAIG, IncA, CiaoPP and MAF receive the
  change as an edit and do no matching. None identifies a function by a
  content hash alone.
- The invalidation rule is, in every summary-based system, "the entity changed
  syntactically, or something in its transitive dependency closure did".
  Goblint's reluctant mode, Boogie's fine-grained mode and CiaoPP's enhanced
  deletion strategy add a semantic check that stops propagation when a
  recomputed result is unchanged.
- Three guarantees appear. Equal to from-scratch: DAIG, demanded
  summarization, IncA/Laddder, Reviser (by experiment), CiaoPP without
  widening. Sound with a paper proof but possibly less precise: the Eva
  prototype with loop-invariant reuse, CiaoPP with widening. Presented as
  sound without a theorem for the incremental mode, and less precise: Goblint;
  MAF tests soundness experimentally. No stated guarantee: Infer.
- No system has a mechanically checked proof of its cross-version reuse. The
  only mechanised result found is an Isabelle proof of partial correctness of
  the top-down solver that Goblint builds on; it does not cover reuse across
  versions.

Among the systems that publish no cross-version reuse of analysis results are
IKOS, Mopsa and the Clang Static Analyzer. Astrée's release notes mention
incremental runs without describing them. Released Frama-C documents
`-save`/`-load`, the experimental `-ast-diff`, and the in-run `-eva-memexec`
cache, and calls incremental analyses "future".

## Systems that reuse results across versions

### Goblint (C, multithreaded, abstract interpretation)

Sources: Erhard et al., "Interactive Abstract Interpretation: Reanalyzing
Whole Programs for Cheap", <https://arxiv.org/abs/2209.10445> (journal version:
<https://link.springer.com/doi/10.1007/s10009-024-00768-9>, not opened); source
code at commit `69e8eb7`,
<https://github.com/goblint/analyzer/tree/69e8eb70b00ffe102e535e8d10c308e2f691b2ec/src/incremental>.
The original paper, Seidl, Erhard, Vogler, "Incremental Abstract
Interpretation" (<https://doi.org/10.1007/978-3-030-41103-9_5>), could not be
opened; its approach is taken here from the description in §3 of the follow-up.

- Unit of reuse: the solver's data, that is, the value of each unknown
  (program point paired with a calling context, plus flow-insensitive globals),
  the `stable` set and the dependency maps of the top-down solver (§2–3 of
  <https://arxiv.org/abs/2209.10445>). Options `incremental.save` and
  `incremental.load` store and load this data in a directory
  (<https://github.com/goblint/analyzer/blob/69e8eb70b00ffe102e535e8d10c308e2f691b2ec/src/config/options.schema.json>).
- Identification: globals of the old and new CIL files are put in maps keyed
  by name and matched by name
  (<https://github.com/goblint/analyzer/blob/69e8eb70b00ffe102e535e8d10c308e2f691b2ec/src/incremental/compareCIL.ml#L312-L344>).
  A function is unchanged when its header, formals and locals match and its
  body is equal under an AST comparison, or under a CFG comparison that also
  says which nodes changed (option `incremental.compare`, values `ast` and
  `cfg`;
  <https://github.com/goblint/analyzer/blob/69e8eb70b00ffe102e535e8d10c308e2f691b2ec/src/incremental/compareCIL.ml#L135-L177>).
  Option `incremental.detect-renames` (default true) tries to match renamed
  locals, parameters, functions and globals (same options file).
- Invalidation rule: change detection is "at the level of function
  definitions". For a changed function, all program points except its start
  and return nodes are new unknowns, and the solver destabilizes everything
  that transitively depends on the return node (§3, "Base incremental
  setting"). With reluctant destabilization the changed function is reanalysed
  first and its callers are destabilized only if the value at the return node
  changed (§3, "Reluctant destabilization"; option
  `incremental.reluctant.enabled`, default false). This is a semantic cut-off.
- Guarantee: not equal to from-scratch. The paper defines a reanalysis as
  from-scratch consistent when its result is less than or equal to the
  from-scratch result, and states that this "in all cases is out of reach",
  because right-hand sides are not monotonic in a context-sensitive setting,
  because of widening and narrowing, and because flow-insensitive unknowns
  accumulate values (§6, RQ2). Restarting selected globals from bottom
  recovers some precision (§4). The paper presents the analysis as sound but
  states no theorem about the incremental solver.
- Mechanised proof: none for the incremental mode. The underlying top-down
  solver has an Isabelle proof of partial correctness
  (<https://www.isa-afp.org/entries/Top_Down_Solver.html>). The proof document
  (<https://isa-afp.org/browser_info/current/AFP/Top_Down_Solver/document.pdf>)
  does not contain the words "incremental", "widening" or "side effect".
- Speedup: on 183 commits of zstd (about 22,000 lines of C, each commit at
  most 50 changed lines), from-scratch analysis takes 3000 to 5000 s. For more
  than 80% of commits the incremental run takes less than 8% of that; with
  incremental postprocessing about 3%; with reluctant destabilization about 2%
  for at least 75% of commits (§6, RQ1). Precision: over sequences of commits,
  at most 5% of program points were less precise than from-scratch for most
  of 17 sequences; one sequence lost precision on 15 to 20% of program points
  and two on more than 60% (§6, RQ2).

### DAIG: demanded abstract interpretation (JavaScript subset, prototype)

Source: Stein, Chang, Sridharan, PLDI 2021, extended version
<https://arxiv.org/abs/2104.01270>.

- Unit of reuse: a cell of an acyclic graph. Cells hold statements and
  abstract states; edges are transfer, join, widen and fix computations (§2,
  §4). A separate memo table maps a function symbol and its input values to
  the result, so a transfer function applied to an abstract state seen before
  is not recomputed (§5.1, rule Q-Miss).
- Identification: cells have unique names derived from program locations,
  loop-iteration indices and hashes of values; "names identify values for
  reuse across edits and queries", and name equality is structural (§2.1, §4).
  An edit is given to the analysis as a change to a named statement cell. The
  paper does not address matching two independently parsed versions.
- Invalidation rule: an edit empties every cell reachable forwards from the
  edited cell; nothing is recomputed until a query needs it. A dirtied loop is
  rolled back to its first iterates (§5.3, rules E-Commit, E-Propagate,
  E-Loop). The rule is purely a dependency closure.
- Guarantee: Theorem 6.1 states that a query result equals the invariant the
  underlying abstract interpreter computes at a global fixed point, for any
  abstract domain with widening; soundness follows as Corollary 6.2.
- Mechanised proof: none. Proofs are on paper, in the appendix.
- Speedup: with an octagon domain on synthetic workloads of 3,000 random
  edits, the incremental and demand-driven configuration answers 95% of
  queries within 1.2 s, more than five times lower than the next best
  configuration at that percentile (§7.3).

### Demanded summarization (Java prototype)

Source: Stein, Chang, Sridharan, TOPLAS 46(1), 2024,
<https://plv.colorado.edu/papers/demanded-summarization-toplas24.pdf>.

- Unit of reuse: one DAIG per pair of procedure and entry abstract state, plus
  summary-dependency edges from call sites to the summaries applied there
  (§2.3, §4, §6.1).
- Identification: by procedure identifier and entry abstract state (§6.1).
  A summary is applied at a call only when "its precondition exactly matches
  the callsite abstract state" (§7.2). Edits are again given to the analysis
  as operations.
- Invalidation rule: dirty forwards inside the edited procedure, then follow
  summary-dependency edges and dirty all transitive callers. The dependencies
  used are those of the pre-edit program; the paper calls this "crucial" for
  correctness (§4.2). The authors note that callers depend only on the summary
  triple, so re-demanding the callee could show the summary unchanged and stop
  propagation, but that this eager work may be wasted; the formal system does
  not do it (§4.2).
- Guarantee: Theorem 5.3, from-scratch consistency with tabulation, including
  recursion and arbitrary domains, on paper. One optimisation that would give a
  more precise result than batch analysis is left out of the formal system
  because it "technically violates from-scratch consistency" (§2.3, footnote
  3). §7.2 describes, without using it in the evaluation, a rule that applies
  a summary whose precondition is weaker than the call-site state; the paper
  says it "clearly violates from-scratch consistency" but "does preserve
  soundness and termination" (§7).
- Mechanised proof: none.
- Speedup: synthetic workload of 2,500 edits, 2.7 s per analysis on average;
  memory grows to 24.1 GB for the demanded configuration (§6.2). Also ten
  BugSwarm Java program pairs of about 45 kLOC each (§6.3); figures are in
  Table 1 and are not transcribed here.

### Infer (compositional, summary-based; Java, C, C++, others)

Sources: `infer-analyze` manual, <https://fbinfer.com/man/next/infer-analyze.1.html>;
source code at commit `b1e38fd`.

- Unit of reuse: the summary of a procedure, stored in the results database
  with its recorded dependencies
  (<https://github.com/facebook/infer/blob/b1e38fdc6991b8b8a4e48c9485caaa4dd7c3bd83/infer/src/IR/Dependencies.mli#L11-L32>).
- Identification: by procedure name. Procedure descriptions and summaries are
  keyed by a unique id derived from the procedure name
  (<https://github.com/facebook/infer/blob/b1e38fdc6991b8b8a4e48c9485caaa4dd7c3bd83/infer/src/IR/Procdesc.ml#L1006-L1012>).
  At capture, `--mark-unchanged-procs` compares the new procedure with the
  previously captured one: same return type, formals of the same types, and
  CFG nodes with equal instructions, successors and predecessors up to a
  renaming of node ids and expression names. If they differ the procedure is
  marked `changed`
  (<https://github.com/facebook/infer/blob/b1e38fdc6991b8b8a4e48c9485caaa4dd7c3bd83/infer/src/IR/Procdesc.ml#L1019-L1075>).
- Invalidation rule: with `--incremental-analysis` and a list of changed files
  (`--changed-files-index`), Infer builds a reverse dependency graph from the
  stored summaries and deletes every summary that transitively depends on (1) a
  deleted procedure, (2) the type environment of a changed file, or (3) a
  procedure marked `changed`
  (<https://github.com/facebook/infer/blob/b1e38fdc6991b8b8a4e48c9485caaa4dd7c3bd83/infer/src/backend/AnalysisDependencyGraph.ml#L12-L69>).
  Dependencies are summary loads, other uses of a procedure such as loading
  its attributes, and source files whose type environment was used. The
  manual describes `--invalidate-only` as removing "any summaries from the
  results database that transitively depend on a changed procedure". There is
  no semantic cut-off: a caller is invalidated even if the callee's new
  summary would be identical.
- Guarantee: none stated in the manual or the source. The demanded
  summarization paper says that issues with incremental dependency structures
  "have manifested in the Infer static analyzer, for example, due to
  insufficiently conservative dependency tracking or invalidation of pre-edit
  summaries using the post-edit dependency structure", and that "a variant of
  the technique described in this paper has recently been implemented in the
  Infer static analyzer" (§1 of
  <https://plv.colorado.edu/papers/demanded-summarization-toplas24.pdf>). It
  does not say that Infer inherits the paper's theorems. The abstract of the
  corresponding talk lists "avoiding flakiness or loss of precision" as a
  challenge (<https://pldi23.sigplan.org/details/infer-2023-papers/8>).
- Mechanised proof: none found.
- Speedup: "on the order of 3x" in continuous integration, reported in §1 of
  the TOPLAS paper above, citing the talk. The benchmark is not published.

### IncA and Laddder (Datalog with lattices; Java)

Sources: Szabó, Bergmann, Erdweg, Völter, OOPSLA 2018,
<https://voelter.de/data/pub/inca-oopsla2018.pdf>; Szabó, Erdweg, Bergmann,
PLDI 2021,
<https://www.pl.informatik.uni-mainz.de/files/2021/04/inca-whole-program.pdf>.

- Unit of reuse: derived Datalog tuples, including lattice values produced by
  recursive aggregation, with their support counts (OOPSLA §4).
- Identification: the program is a set of base relations, one per AST node
  type plus `Next` and `Parent`. The IDE maintains these relations and reports
  changes as tuple insertions and deletions, by incremental parsing, tree
  diffing or projectional editing (OOPSLA §3.1). Identity is the AST node
  identity kept by the editor.
- Invalidation rule: the DRedL algorithm deletes all tuples that transitively
  depend on a deleted tuple, re-derives those that still have support, then
  applies insertions. A deletion paired with an insertion of a larger lattice
  value is treated as a monotonic replacement and avoids over-deletion (OOPSLA
  §3.2, §4.3).
- Guarantee: requirement R1, "an incremental analysis must produce the exact
  same result as re-running the analysis from scratch" (OOPSLA §2). It holds
  under stated assumptions; the main one is that recursive rules and
  aggregations are monotonic, which "is the responsibility of the analysis
  developer" (OOPSLA §4.1). Laddder loosens the monotonicity requirement and
  admits aggregators that act as widenings (PLDI §4.3).
- Mechanised proof: none. The introduction of the OOPSLA paper says "formally
  verified"; §4.5.2 gives "an informal sketch". Laddder gives proof sketches
  (PLDI §4.3, §6).
- Speedup: IncA on four Java code bases up to 70 kLOC (BerkeleyDB):
  initialisation 6.5 s to 64.3 s for points-to analysis, updates in a few
  milliseconds on average, memory up to 5 GB (OOPSLA §6). Laddder on Java code
  bases up to 105 kLOC (ant): sub-second updates for more than 99% of changes
  (PLDI §7, §9).

### CiaoPP (constraint logic programs, context-sensitive)

Source: Garcia-Contreras, Morales, Hermenegildo, "Incremental and Modular
Context-sensitive Analysis", <https://arxiv.org/abs/1804.01839>.

- Unit of reuse: entries of the analysis graph, each a predicate with a call
  pattern and its answer, kept per module, with the dependency edges between
  them (§3–5).
- Identification: the algorithm takes the change as a set of added and
  deleted clauses (§4.1). Predicates are referred to by name and module (§2).
  Matching two source versions is not described.
- Invalidation rule: for a deleted clause, remove the entries that depend on
  it and recompute. Across modules, entries that relied on an imported answer
  that is now larger than the current one are removed as "potentially
  imprecise" (§5.1). A refinement reanalyses first and keeps
  entries whose results are unaffected (§5.1, "Enhancing the deletion
  strategy").
- Guarantee: correctness of the incremental result for clause addition and
  deletion (Theorems 2–4 and 7 in §4, Theorem 9 in §6). Precision equal to the
  least fixed point, hence to from-scratch, when no generalization by widening
  is used (Theorems 5, 6 and 8 in §4). All on paper.
- Mechanised proof: none.
- Speedup: benchmarks in §7 (hanoi, bid, warplan, boyer, ann and others), times
  in Table 3 and Fig. 13; not transcribed here.

### Boogie/Dafny (deductive verification, included for its invalidation scheme)

Source: Leino, Wüstholz, "Fine-grained Caching of Verification Results", CAV
2015,
<https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/krml245.pdf>.

- Unit of reuse: the verification result of a procedure implementation, and
  in the fine-grained mode the status of individual checked statements (§2–3).
- Identification: by entity. The front end supplies an entity checksum for
  each function, procedure and implementation, computed as a hash of the AST
  parts used to generate it, which makes it insensitive to comments and
  whitespace (§2.1).
- Invalidation rule: Boogie derives a dependency checksum from the entity's
  own checksum and the dependency checksums of what it depends on directly,
  such as callees. A cached result is reused if the dependency checksum is
  unchanged. A change to a callee's specification invalidates callers; a change
  to only a callee's body does not (§2.1). Statement checksums hash a
  statement's text and the checksums of the statements before it in control
  flow (§3.0).
  When only a callee changed, the cached result is kept as "partially
  verified" under an explicit assumption that the verifier then checks (§3.1).
- Guarantee: the paper does not state a theorem.
- Mechanised proof: none.
- Speedup: eight recorded Dafny IDE sessions; basic caching is more than an
  order of magnitude faster than no caching for many sessions, and
  fine-grained caching a further 17% faster on average (§4).

### Reviser (IFDS/IDE data-flow analysis, Java)

Source: Arzt, Bodden, technical report TUD-CS-2013-0253 (ICSE 2014 paper),
<https://download.hrz.tu-darmstadt.de/pub/FB20/Dekanat/Publikationen/CASED/TUD-CS-2013-0253.pdf>.

- Unit of reuse: jump functions and summary functions of the IDE solver
  (overview of the IDE framework).
- Identification: a structural diff of the interprocedural control-flow graphs
  of the two versions; a modified statement is a deleted node plus an added
  node (section "Computing Changesets").
- Invalidation rule: "clear-and-propagate": clear the information that depends
  on changed nodes, then propagate again from there (abstract).
- Guarantee: "the same results as a full recomputation" (introduction),
  established by experiment (section "Implementation Correctness").
- Mechanised proof: none.
- Speedup: about 80% of analysis time saved compared with a full recomputation
  (abstract, introduction).

### MAF incremental modular analysis (Scheme)

Source: Van der Plas, Stiévenart, De Roover, "Result Invalidation for
Incremental Modular Analyses", VMCAI 2023,
<https://qstievenart.gitlab.io/pdfs/vmcai2023.pdf>.

- Unit of reuse: components (function calls with their context), a global
  store, and the dependencies between them (§2.1).
- Identification: none needed. Both versions are written in one program using
  "change expressions" (§2.2).
- Invalidation rule: three strategies that interleave invalidation with
  recomputation, removing outdated components, dependencies and store
  contributions (abstract, §3).
- Guarantee: no theorem. Soundness was tested experimentally and "no unsound
  results were encountered" (evaluation section). The strategies improve
  precision "though the precision of a full reanalysis is not yet matched"
  (abstract).
- Mechanised proof: none.
- Speedup: reported per benchmark in the paper's evaluation; not transcribed.

### Eva prototype (ECOOP 2025)

Source: Razafintsialonina, Bühler, Miné, Perrelle, Signoles, "Reusing Caches
and Invariants for Efficient and Sound Incremental Static Analysis",
<https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2025.28>.
The paper gives its implementation as a branch of the public Frama-C
repository, `publi/2025-ecoop-rbmps`. It is not part of a Frama-C release, and
the code was not read for this note.

- Unit of reuse: a function summary and a loop invariant. A summary is the
  input state restricted to the read locations, the read set, the output
  state restricted to the written locations, and the written set (§5).
- Identification: functions are matched by name. Two functions are "similar"
  if their ASTs have the same shape and instructions, the global variables
  they access are the same and unmodified, and the functions they call are
  similar (§5). Loops are matched inside matched functions; the paper says
  this matching "might be incorrect" and that this does not affect soundness
  (§6). Renaming detection is left to future work (§5).
- Invalidation rule: a summary is dropped if its function is not similar to
  the old one, which includes a change in a callee or in an accessed global
  (§5, Example 10; §7.1). A kept summary applies at a call when the new input
  state equals the stored one on the read set (§5). With the read-set
  condition alone, functions that allocate memory and their callers cannot
  use summaries; §5 adds the condition that the new and stored input states
  allocate the same abstract locations. The implementation uses a different
  condition, that the stored set of allocated locations is disjoint from the
  domain of the new input state (§7.1). Loop invariants are never invalidated:
  any stored invariant may seed the iteration (§6, §7.1).
- Guarantee: on paper, for the paper's language. Theorem 15: reusing a
  summary is a safe approximation if the new and old input states agree on
  the read locations and the statement allocates the same set of locations
  with both. Theorem 20: the loop iteration started from any stored invariant
  is sound and terminates. Summaries are "always precise" for functions not
  impacted by the change; loop-invariant reuse may lose precision (§1). The
  proof for the allocation condition as implemented in Eva "is left for future
  work" (§7.1).
- Mechanised proof: none.
- Speedup: successive commits of PolarSSL, Monocypher and Chrony. Incremental
  runs are faster than full runs for all programs when summaries and loop
  invariants are both reused; some Chrony commits are slower with summaries
  alone because many summaries are invalidated; memory use is higher. Runs
  that reuse loop invariants raise slightly more alarms than the baseline
  (§7.3, Figs. 8–9, Table 3; figures not transcribed).

### CPAchecker precision reuse (a different design)

Source: Beyer, Löwe, Novikov, Stahlbauer, Wendler, "Reusing Precisions for
Efficient Regression Verification", <https://arxiv.org/abs/1305.6915>.

The stored object is the precision (the predicates or variables to track),
scoped by function name or location number, not an analysis result. The next
revision is verified in full, starting from that precision. The paper states
that a wrong precision file leaves the result correct and affects only
performance (Section III). Evaluated on 59 Linux device drivers with 1,119 revisions.
No invalidation rule is needed because nothing reused is trusted.

## Frama-C

What released Frama-C documents, from this repository:

- `-save` and `-load` write and read the whole session. On load with
  unchanged parameters Frama-C does not redo the value analysis; if a parameter
  the analysis depends on is changed, it "discards the saved results of the
  value analysis and recomputes it on the same source code"
  (`doc/userman/user-services.tex`, section "Saving and Loading Projects";
  published manual: <https://frama-c.com/download/frama-c-user-manual.pdf>,
  whose text was not compared with this checkout). The
  unit is the whole analysis and the program is the same one.
- The Eva manual presents `-save`/`-load` as a way to separate parsing,
  analysis and viewing, so that "partial results can be saved and reused"
  (`doc/eva/main.tex`, sections "Three-step approach" and "Saving the result
  of an analysis"; published manual:
  <https://frama-c.com/download/frama-c-eva-manual.pdf>, not compared with
  this checkout). It does not describe
  reuse across versions of the analysed program.
- `-ast-diff` is documented as experimental. It computes the difference
  between a loaded AST and the AST of the current sources "to help support for
  future incremental analyses (which recompute results only for the modified
  AST parts and their dependencies)"; the difference "can be used by plug-ins
  which support it" (`doc/userman/user-sources.tex`, section "Incremental
  parsing"). The same section says that non-modular analyses "need to be
  recomputed in their entirety even for minuscule AST changes". The option
  dates from Frama-C 25.0 (`Changelog`).
- The interface of `-ast-diff` maps each new function to `Same`, `Not_present`
  or a partial status: `Spec_changed`, `Body_changed`, `Callees_changed`,
  `Callees_spec_changed`
  (`src/kernel/services/ast_queries/ast_diff.mli`). The candidate for a
  function is looked up by name (`find_candidate_func` in
  `src/kernel/services/ast_queries/ast_diff.ml`). In this checkout no file
  under `plugins/` refers to `Ast_diff`.
- `-eva-memexec` is on by default and is described as "Speed up analysis by
  not recomputing functions already analyzed in the same context"
  (`plugins/eva/src/parameters.ml`). The cache is keyed by function, argument
  values, a set of "useful input bases" and an input state; an entry holds the
  set of bases possibly read or written by the call and the resulting states
  (`plugins/eva/src/engine/mem_exec.ml`, `mem_exec.mli`). Its table is built
  with `Eva_utils.Do_Not_Marshal`, which is documented as making tables "which
  should not be saved on disk" (`plugins/eva/src/utils/eva_utils.mli`). The
  option does not appear in `doc/eva/main.tex`.

Released Frama-C therefore documents reuse within one run (memexec), reuse of
a whole analysis of the same program (`-save`/`-load`), and an AST difference
meant for later use. It documents no reuse of Eva results across program
versions. The ECOOP 2025 prototype above is the published work that does it.

## Analyzers with no documented cross-version reuse of analysis results

- IKOS. The analyzer manual documents a result database `output.db` for
  reports and an option `--no-fixpoint-cache` to "disable the cache of fixpoint
  for called functions", which is a cache within one run
  (<https://github.com/NASA-SW-VnV/ikos/blob/ac7f7c1738976cabc58c6a53413df6e458995c38/analyzer/README.md>).
  A code search for "incremental" in the repository returns one test file.
- Mopsa. The source has a bounded in-memory cache of post-conditions and
  evaluations
  (<https://gitlab.com/mopsa/mopsa-analyzer/-/blob/f168a9c025738d4940cfb6a281dde258c871da73/analyzer/framework/core/cache.ml>)
  and an interprocedural iterator that caches the last analyses of a function,
  default size 3
  (<https://gitlab.com/mopsa/mopsa-analyzer/-/blob/f168a9c025738d4940cfb6a281dde258c871da73/analyzer/languages/universal/iterators/interproc/sequential_cache.ml>).
  Only parsed ASTs are cached on disk, checked against file modification
  (<https://ocaml.org/p/mopsa/1.2/mopsa.mopsa_c_parser/Mopsa_c_parser/Clang_parser_cache/index.html>).
  The user manual was not searched.
- Clang Static Analyzer. Its cross-translation-unit documentation covers
  importing definitions from other translation units and does not mention
  incremental analysis
  (<https://clang.llvm.org/docs/analyzer/user-docs/CrossTranslationUnit.html>).
  CodeChecker, which drives it, documents incremental analysis at file level:
  analyse only the changed files and the files that depend on them, and update
  the report directory
  (<https://github.com/Ericsson/codechecker/blob/57e6d8a928ddbb9d92b709ad2efdf65daeb2b587/docs/usage.md#step-4-incremental-analysis>).
- Astrée. Release notes mention "incremental analysis" when re-running an
  analysis on the server, and a fix for "false positives and/or false
  negatives when re-running an analysis project on the server (incremental
  run)" (<https://www.absint.com/releasenotes/astree/24.04>,
  <https://www.absint.com/releasenotes/astree/24.10>). The same notes list
  "incremental preprocessing, parsing, and rule checking" for the C++ front
  end. They do not say what is reused, how files or functions are matched, or
  what guarantee holds. An older note adds a loop invariant cache within a run
  (`cache-iterates`, <https://www.absint.com/releasenotes/astree/11.12>). The
  user manual is not public.
- Differential Datalog. The engine is incremental by construction; its README
  says it performs "the minimum amount of work necessary to compute changes to
  output relations"
  (<https://github.com/vmware/differential-datalog/blob/ca5ded823dc2c01bc33aac44e526c12d2fed03a6/README.md>).
  No abstract-interpretation analyzer built on it was examined.

## Comparison

| System | Unit of reuse | Identity across versions | Invalidation rule | Stated guarantee | Proof | Reported gain |
|---|---|---|---|---|---|---|
| Goblint | Solver unknowns, stable set | Global name, then AST or CFG comparison, optional rename detection | Changed function, then transitive dependents; reluctant mode stops if the return value is unchanged | Not equal to from-scratch; precision can degrade | Paper, none for incremental mode; Isabelle for the base solver only | 2–8% of from-scratch time on most of 183 zstd commits |
| DAIG | Graph cells, memo table on inputs | Structural cell names; edits given as operations | Forward dependency closure, lazy recomputation | Equal to from-scratch (Thm 6.1) | Paper | 95% of queries within 1.2 s, synthetic edits |
| Demanded summarization | DAIG per procedure and entry state | Procedure id and entry state | Closure over summary dependencies of the pre-edit program; all transitive callers | Equal to from-scratch (Thm 5.3) | Paper | 2.7 s mean, synthetic; BugSwarm pairs |
| Infer | Procedure summary | Procedure name, then structural CFG equality | Transitive reverse dependencies of changed or deleted procedures and of changed type environments | None stated | None | About 3x in CI, benchmark not published |
| IncA / Laddder | Datalog tuples and lattice aggregates | AST node identity kept by the IDE | Delete dependents, re-derive, insert (DRedL) | Equal to from-scratch under monotonicity assumptions | Paper sketch | Milliseconds per change, Java up to 105 kLOC |
| CiaoPP | Call-pattern/answer entries per module | Not described; changes given as added and deleted clauses | Remove entries depending on deleted clauses or on imprecise imports | Correct; equal to from-scratch without widening | Paper | See paper |
| Boogie/Dafny | Verification result per implementation or statement | Entity, with AST checksum from the front end | Dependency checksum over callees; assumptions re-checked in fine-grained mode | None stated | None | Over 10x for many IDE sessions, plus 17% |
| Reviser | IDE jump and summary functions | Structural diff of interprocedural CFGs | Clear and propagate from changed nodes | Same as full recomputation, by experiment | None | About 80% time saved |
| MAF | Components, store, dependencies | Change expressions in one program | Interleaved invalidation and recomputation | Soundness tested experimentally; less precise than full reanalysis | None | See paper |
| Eva prototype (ECOOP 2025) | Function summary on read and written sets; loop invariant | Function name, then AST shape, accessed globals, similar callees | Function not similar (itself, a callee or an accessed global changed); then input equal on the read set. Loop invariants never invalidated | Sound; summaries precise, invariants may lose precision | Paper; allocation condition unproved | Faster on PolarSSL, Monocypher, Chrony commits; see paper |
| CPAchecker | Precision, not results | Function name or location number | None needed | Sound whatever the file contains | None | 59 drivers, 1,119 revisions |
| Frama-C releases | Whole saved session; in-run memexec | Same program only; `-ast-diff` experimental | Analysis parameter change discards results | Not applicable | Not applicable | Not applicable |
| IKOS, Mopsa, Clang SA | In-run caches only; files for CodeChecker | Not applicable | Not applicable | Not applicable | Not applicable | Not applicable |

## Design choices

Choices that recur:

1. Identity by name first, structure second. The systems that match two
   parsed versions start from the function name and then compare bodies
   structurally (Goblint, Infer, the Eva prototype, `-ast-diff`). Reviser
   diffs the interprocedural CFGs. Checksums of the AST play the role of the
   structural comparison in Boogie.
2. Dependencies are recorded while analysing, not derived from the syntax
   afterwards: solver influence maps in Goblint, summary loads in Infer,
   summary-dependency edges in demanded summarization, tuple support in IncA.
3. Invalidation is over-approximate and is a transitive closure over those
   recorded dependencies.
4. A change in a callee invalidates the callers' stored results in every
   summary-based system, unless a semantic check intervenes.
5. Type and global declarations are dependencies in their own right: Infer
   tracks the type environment of each source file, and the Eva prototype
   treats a modified accessed global as a change to the function.
6. Proofs are on paper. The only mechanised proof concerns a solver without
   incrementality.

Choices that are contested:

1. Equal to from-scratch, or only sound. DAIG, demanded summarization, IncA
   and Reviser require equality and present its absence as "flakiness".
   Goblint states that equality is out of reach with widening, non-monotonic
   right-hand sides and accumulated globals, and measures the loss. The Eva
   prototype accepts loss for loop invariants and not for summaries.
2. Semantic cut-off. Goblint's reluctant mode, Boogie's fine-grained mode and
   CiaoPP's enhanced deletion strategy stop propagation when the recomputed
   result is the same. Infer and the
   formal system of demanded summarization invalidate all transitive callers;
   the latter names the cut-off as possible and questions its cost.
3. Granularity of change detection. Whole function (Goblint by default, Infer,
   the Eva prototype), CFG node (Goblint with `incremental.compare=cfg`, DAIG,
   Reviser), statement checksum (Boogie), AST node (IncA).
4. Handling of renames. Goblint detects them by default, Infer compares up to
   renaming of node ids and expression names, the Eva prototype leaves it to
   future work, and name-keyed schemes treat a renamed function as deleted and
   added.
5. Which dependency structure to use when invalidating. Demanded summarization
   insists on the pre-edit dependencies and reports that using post-edit
   dependencies caused errors in Infer.
6. Reusing a result that is known to be stale. The Eva prototype reuses loop
   invariants of modified loops and CPAchecker reuses precisions, both as
   starting points that the analysis re-validates. The other systems discard
   anything stale.
7. Keying a summary by the memory it reads. Eva's memexec and the Eva
   prototype restrict the key to the read set. Demanded summarization requires
   the summary precondition to match the call-site state exactly, and treats
   applying a weaker precondition as an optional extension that gives up
   equality with from-scratch. DAIG's memo table is keyed on the full input
   values.
8. Eager or lazy recomputation after invalidation. DAIG recomputes on demand;
   Goblint and Infer recompute everything reachable from the entry point or
   the changed files.

## Sources not accessed and points not documented

- Seidl, Erhard, Vogler, "Incremental Abstract Interpretation" (2020): the
  Springer page did not load. Not read.
- The journal version of the Goblint paper and the CAV 2024 paper on the
  verified top-down solver: Springer pages did not load. The arXiv version and
  the AFP entry were read instead.
- The HAL record of a paper on revision tracking in Astrée
  (<https://hal.archives-ouvertes.fr/hal-01192985>) returned a bot check. Not
  read, not used.
- Slides of the talk "Incremental Analysis in Infer": only the abstract is
  public on the conference page.
- The Astrée user manual is not public.
- Speedup tables of CiaoPP, MAF, demanded summarization (BugSwarm) and the Eva
  prototype were located but not transcribed.
- No source states whether Infer's incremental result equals a from-scratch
  result.
- The Mopsa user manual and the IKOS issue tracker were not searched.
- Leads found by search and not examined: a paper on fixpoint reuse for
  incremental JavaScript analysis
  (<https://cs.ucsb.edu/sites/default/files/documents/worklist-reuse.pdf>); a
  CEA List page on incremental software verification
  (<https://list.cea.fr/en/incremental-software-verification-for-cybersecurity/>),
  which did not load; two further MAF papers
  (<https://qstievenart.gitlab.io/pdfs/scam2023.pdf>,
  <https://soft.vub.ac.be/Publications/2025/vub-tr-soft-25-12.pdf>).
