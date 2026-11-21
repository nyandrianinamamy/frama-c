# Issue 88 third-round review

**Reject** at `0ea12c8e3d66ff721d3eda88a48001cb68fd0374`. The eight-commit range starts after `cada4ccf24`. The differential reference build for the new regressions was `d84d3149e4f35867bf4d728a4d68506287108908`. I read #88 and #93 through #96 via gh. The failures below use cvalue, fixed allocation, and nonrecursive calls. The builtin in one variant copies zero bytes.

Run `bash replay.sh` from this directory. Each command below uses `run.sh` to select the installed binary, activate the requested switch, set TERM=xterm, and check the environment. For a cache comparison, run the printed command once as written and once with the extra argument `-eva-no-memexec`. The only builds are of the two observer modules in this directory, using Dune with eight jobs.

## FAIL — raw-state selection loses a dependency

[old.c](old.c) contains an empty function with this body contract.

```c
/*@ requires k == 1;
    ensures a <= (\old(1 \in (1 .. k)) ? g : 9); */
void f(void) {}
```

Command `bash run.sh after old.c`, both modes. Both calls reset k to {0,1} and a to [0..9]. Only g changes from 3 to 9. Expected second=[0..9]. Cached Eva hits f, pastes second={0,1,2,3}, and skips the second valid postcondition evaluation. Fresh Eva gives [0..9]. See [on](after.old.on.log) and [off](after.old.off.log).

`bash run.sh after guard.c` [isolates the premise](guard.log). The identical membership test is invalid in the raw state and valid in reduced Old. In eval_terms.ml:1213 a range with bottom underapproximation is marked potentially empty. At :2858 the subset evaluator uses that flag to report False for a definitely nonempty left operand, even when the right set *may* contain that operand. At :1459 eval_tif takes only the false arm. The inclusion asserted in logic_inout.ml:202 holds for the states, but the dependency argument requires monotonicity of this particular evaluator. Here it skips g.

[behavior.c](behavior.c) puts the guard in an assumes clause of a declaration with a default requirement. Command `bash run.sh after behavior.c`, both modes. Expected [0..9]. Actual cached {0,1,2,3} with f hit, fresh [0..9]. See [on](behavior.on) and [off](behavior.off). logic_inout.ml:94 computes activity on raw pre, and :137 filters postconditions using it. The behavior becomes active after default precondition reduction. Walking both arms of a conditional alone would leave this failure.

[spec.c](spec.c) puts the guard in an assigns destination. Command `bash run.sh after spec.c -eva-builtin choose:Frama_C_memcpy`, both modes. Expected second call prevents main returning. Cached Eva hits f and returns with second={4,5,6,7,8,9}. Fresh Eva reports NON TERMINATING FUNCTION. This one adds reachability. See [on](after.spec.on.log) and [off](after.spec.off.log). In raw pre the destination evaluates to null. logic_inout.ml:320 treats an empty valid part as no write, so reconstruction succeeds, although in reduced pre Eva writes p and its postcondition reads t. The public probe on the same declaration reports k, p and dest, omitting t ([output](spec-zone.log), exact command in replay.sh). The explicit exception path does return top on the tracked opaque-destination test. Empty-success bypasses it.

Correct the potentially-empty subset evaluation and preserve reads across every state in which Eva actually evaluates the contract. Preserve these three cases as regressions. All three expose the same invalid inference at different consumers.

## FAIL — partitioning directives read memory outside the annotation key

[unroll.c](unroll.c), `bash run.sh after unroll.c`, both modes. The only use of budget in f is its loop annotation. Changing 12 to 1 gives a second-call hit and second={42}. Fresh Eva emits the partial-unrolling diagnostic and gives {0,42}. See [on](after.unroll.on.log) and [off](after.unroll.off.log). The loop budget goes through partitioning_parameters.ml:86 and partition.ml:695. Dynamic unroll budgets were also identified in the earlier #87 audit.

[split.c](split.c), `bash run.sh after split.c`, both modes. The only use of g in f is its split annotation. Changing 0 to [0..1000] leaves answer=1 in both modes. Fresh Eva warns that a split on 1001 values exceeds the limit of 100. The hit skips the warning. See [on](after.split.on.log) and [off](after.split.off.log). partition.ml:529 evaluates the split expression and :558 checks its cardinality. operational_inputs.ml:366 handles assertions and loop invariants and skips both engine directives. The result of the cvalue domain-extension audit does not cover these engine consumers.

## FAIL — repeated ordinary evaluation of nested conditionals

[nested20.c](nested20.c) has one check with 20 nested conditionals. Its expression is formed by replacing E with ((E)==g ? h : j), starting from g. Command `bash run.sh after raw -no-autoload-plugins -load-module eva -eva -eva-no-memexec nested20.c`, and replace after by before for the reference. The result/status agrees. At depths 10, 15 and 20 a timed run used 0.06, 0.21 and 5.03 seconds user CPU on HEAD against 0.06, 0.05 and 0.05 seconds on d84. Host times can vary. See [timing script](extras.sh). eval_terms.ml:1452 asks for the condition's dependencies on every ordinary evaluation. At :1459 evaluation of the condition revisits the same child. A condition containing a conditional consequently duplicates work at each level. Keep complete dependencies for clients that request them without repeating this traversal at each nested ordinary evaluation.

## Cache precision and external callers

- [loss.c](loss.c), `bash run.sh before loss.c` and `bash run.sh after loss.c`. A body with assigns p from &x sets p=&x. With identical input on both calls, d84 hits and HEAD analyzes f twice. Both give answer=1. [Before](before.loss.on.log), [after](after.loss.on.log). The optional checker is disabled. logic_inout.ml:162 passes &x to an lvalue-only operation, which raises and yields top. The checker itself catches an unsupported location and supplies bottom at :483. For bare &x the answer is independent of memory. The same unconditional checker footprint accounts for the three lost realpath hits on the previously reported oracle. Its result-relative destination cannot be resolved in pre. Safe fallback to top explains the change, but the hit cost is avoidable when the checker is disabled, or when the checker outcome can be shown invariant. This is a concrete additional loss outside the suite. No production hit-rate estimate.
- [api.c](api.c) and [zones.ml](probe/zones.ml) call the kernel's Logic_deps.from_stmt_annot on a check of a[strlen((char *)text)]. Before it returned a[2]. After it also contains the text base. The exact two commands and module paths are in [commands.log](commands.log). [Before](before.api.log), [after](after.api.log). Including the pointed string is justified. PDG annot.ml:98 and slicingCmds.ml:494 consume that kernel answer. An unsupported strict location subterm can instead give None through logic_deps.ml:380. No end-to-end graph or slice comparison was run. Studia studia_request.ml:93 consumes only over. From from_compute.ml:48 uses under/over, which are evaluated independently of strict address dependencies. The replay of the zones test preserves From's a[0..3] FROM nothing (and SELF) on both revisions, while InOut inputs go from nothing to top.
- Suppressing the dependency walk's bottom-let warning and two range-bound messages is justified. The controls distinguish the ordinary bottom-let warning under -eva-reduce-on-logic-alarms (present on both revisions) from the comprehension dependency walk warning (only on d84). The implementation still guards ordinary range diagnostics on silence at eval_terms.ml:1195. The rewritten binding evaluates its RHS once and uses the same backward equality operation and exact-location reduction as reduce_left_by_relation at :2206. The two existing range-message removals were assessed from the recorded suite diff and source. I did not independently replay the whole logic.0 or stdlib_c.0 tests.

## Regression evidence

[oracle-results.txt](oracle-results.txt) records actual generated default flags, inputs, module, and byte comparisons with tracked stdout and stderr. Both builds ran all 62 invocations. HEAD matches all 62. On d84, 33 differ and 29 already match. All seven new C files have at least one discriminating invocation. In particular, both spec_pre_case invocations already pass on d84 because another zone inhibits reuse. Its separate spec_deps observer discriminates k;p before from ANYTHING after. Both ordinary_let_case invocations already pass, as expected of a preservation control. Most fresh controls already pass. Seven effects cases, nine term cases, both checker cases and the prior conditional, pointer, let, asm and tagged-assumes cases have discriminating cached runs. The tests correctly exercise the reported earlier fixes.

The full default plug-in suites, named Eva configurations, lint, headers, and #94–96 reproducers were not rerun in this review. I relied on the coordinator's stated scope for those results. I did not verify other abstract domains, every logic constructor, or checker behavior for every third-party client. No source or oracle in the three checkouts was edited or promoted.
