Plug-in readers of Eva's results and Eva's semantic reports (prototype, see
plugins/inout/prototype-state-query). Only Eva and InOut are loaded
explicitly; Callgraph and Server come with their dependencies.

Three processes run the same requests. The reference runs fresh-only Eva on
the legacy path (no memexec, no hit log) with the guard off. The legacy run
is the candidate on the legacy path (-eva-no-hit-log): the guard records
the reads of each request. The candidate records the hit log.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance plugins-reference -inout-state-query-acceptance-output reference.jsonl plugins.i > reference.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance plugins-candidate plugins.i > legacy.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance plugins-candidate -inout-state-query-acceptance-output candidate.jsonl plugins.i > candidate.log 2>&1
  $ for run in reference legacy candidate; do sed -n -e 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' $run.log > $run.answers; done

Completion of the analysis. Server's filters and Callgraph ask whether Eva
has computed its results before reading them. On the legacy path, this
reads the computation state of Eva; the candidate answers from the
completion of the hit log.
  $ grep -e "call analysis\.is_computed" legacy.log candidate.log
  legacy.log:[acceptance] call analysis.is_computed legacy-reads=1 resolved=0 answer=true
  candidate.log:[acceptance] call analysis.is_computed legacy-reads=0 resolved=1 answer=true
  $ grep -e "^analysis\.is_computed" reference.answers
  analysis.is_computed true

Call relations. On the legacy path, each request reads Eva's table of call
relations. The candidate serves them from the callstacks of the recorded
invocations: one resolution, no legacy read. The answers are those of the
reference: dead_callee is only called in a dead branch, ptr3 is in the
table of function pointers but never called, and uncalled is never called.
  $ grep -e "^\(is_called\|callers\|callsites\)\." candidate.answers > relations.txt
  $ grep -e "^\(is_called\|callers\|callsites\)\." reference.answers | diff - relations.txt
  $ cat relations.txt
  is_called.dead_callee false
  callers.dead_callee none
  callsites.dead_callee none
  is_called.g true
  callers.g main
  callsites.g main@43,44
  is_called.h true
  callers.h main
  callsites.h main@41,42
  is_called.leaf_a true
  callers.leaf_a h g
  callsites.leaf_a h@27 g@35
  is_called.leaf_b true
  callers.leaf_b h
  callsites.leaf_b h@27
  is_called.main true
  callers.main none
  callsites.main none
  is_called.never_returns true
  callers.never_returns main
  callsites.never_returns main@56
  is_called.ptr1 true
  callers.ptr1 main
  callsites.ptr1 main@45
  is_called.ptr2 true
  callers.ptr2 main
  callsites.ptr2 main@45
  is_called.ptr3 false
  callers.ptr3 none
  callsites.ptr3 none
  is_called.uncalled false
  callers.uncalled none
  callsites.uncalled none
  $ grep -c -e "call \(is_called\|callers\|callsites\)\.[^ ]* legacy-reads=1 resolved=0 " legacy.log
  33
  $ grep -c -e "call \(is_called\|callers\|callsites\)\.[^ ]* legacy-reads=0 resolved=1 " candidate.log
  33

Guard outcomes. Each call to h takes one branch of its conditional, and
only the second call to g takes the then branch of x > 1: the outcomes join
those of every analysis of the function. The test y < 0 in main never
holds. On the legacy path, each request reads Eva's table of guard
outcomes; the candidate joins the outcomes recorded with each analyzed
body.
  $ grep -e "^guard\." candidate.answers > guards.txt
  $ grep -e "^guard\." reference.answers | diff - guards.txt
  $ cat guards.txt
  guard.g@34 then=true else=true
  guard.h@27 then=true else=true
  guard.main@46 then=false else=true
  guard.main@56 then=true else=true
  $ grep -c -e "call guard\.[^ ]* legacy-reads=1 resolved=0 " legacy.log
  4
  $ grep -c -e "call guard\.[^ ]* legacy-reads=0 resolved=1 " candidate.log
  4

Control: a resolver that rebuilds each visit from the first producer of its
function takes the outcomes of the first call to h and to g for both calls.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance plugins-wrong-producer plugins.i > wrong.log 2>&1
  $ sed -n -e 's/^\[acceptance\] call \(guard\.[^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' wrong.log | diff guards.txt -
  1,2c1,2
  < guard.g@34 then=true else=true
  < guard.h@27 then=true else=true
  ---
  > guard.g@34 then=false else=true
  > guard.h@27 then=true else=false
  [1]

Annotation statuses after the analysis. Eva marks the postconditions of an
analyzed function as dead when its return statement is unreachable, as for
never_returns. On the legacy path, it reads the analysis status of each
function to tell whether its body was analyzed; the candidate tells it from
the invocations of the hit log. It then asks whether statements are
reachable, which the hit log answers. Eva then refines the statuses of the
alarms and of the assertions that use a C label, from the states of each
callstack, which the hit log answers too. The read left in the candidate
is the initial state of the logic, which the evaluation of a predicate
reads through Eva.Eval_terms.add_init (see the readers in the JSON
records).
  $ grep -e "execution phase=post-analysis reader=Eva.Eval_annots" legacy.log candidate.log
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=getter store=cvalue
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=enumeration store=cvalue
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=availability store=analysis-status
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=getter store=cvalue
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=enumeration store=cvalue
  candidate.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=getter store=cvalue
  $ grep -o -e '"readers":\["Eva.Eval_annots.mark_green_and_red"[^]]*\]' candidate.jsonl
  "readers":["Eva.Eval_annots.mark_green_and_red","Eva.Eval_terms.add_init"]
