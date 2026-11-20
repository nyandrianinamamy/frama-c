Plug-in readers of Eva's results and Eva's semantic reports (prototype, see
plugins/inout/prototype-state-query). Only Eva and InOut are loaded
explicitly; Callgraph and Server come with their dependencies.

Three processes run the same requests. The reference runs fresh-only Eva on
the legacy path (no memexec, no hit log) with the guard off. The legacy run
is the candidate on the legacy path (-eva-no-hit-log): the guard records
the reads of each request. The candidate records the hit log.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance plugins-reference -inout-state-query-acceptance-output reference.jsonl plugins.i > reference.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance plugins-candidate -inout-state-query-acceptance-output legacy.jsonl plugins.i > legacy.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance plugins-candidate -inout-state-query-acceptance-output candidate.jsonl plugins.i > candidate.log 2>&1
  $ for run in reference legacy candidate; do sed -n -e 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' $run.log > $run.answers; done

The plug-ins loaded, with autoload disabled: Eva and InOut, and the
plug-ins they depend on. The optional server API of Eva is not loaded.
  $ grep -o -e '"plugins":[^]]*],"eva_server_api":[a-z]*' candidate.jsonl
  "plugins":["Callgraph","Eva","Frama-C kernel","Inout","Server"],"eva_server_api":false

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

The same control changes InOut's outputs of g and h, and of the statement
of each that only one of its calls executes, and the coverage of Eva's
statistics, which Eva computes after the analysis from the answers of the
resolver. Every other answer is that of the reference.
  $ sed -n -e 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' wrong.log > wrong.answers
  $ diff reference.answers wrong.answers | sed -n -e 's/^> \([^ ]*\) .*/\1/p'
  guard.g@34
  guard.h@27
  inout.kf_outputs.g
  inout.kf_external_outputs.g
  inout.kf_outputs.h
  inout.kf_external_outputs.h
  inout.stmt_outputs.g@34#2
  inout.stmt_outputs.h@27#3
  statistics.semantic

Callgraph. The request recomputes the graph from Eva's call relations: one
read per function on the legacy path, one resolution per function in the
candidate. Every function is a vertex, but no edge leads to dead_callee nor
to ptr3, which the syntactic graph has. The second request reuses the
memoized graph and reads nothing.
  $ grep -e "^callgraph\." candidate.answers > callgraph.txt
  $ grep -e "^callgraph\." reference.answers | diff - callgraph.txt
  $ cat callgraph.txt
  callgraph.edges vertices: dead_callee g h leaf_a leaf_b main never_returns ptr1 ptr2 ptr3 uncalled; edges: g@35->leaf_a h@27->leaf_a h@27->leaf_b main@41->h main@42->h main@43->g main@44->g main@45->ptr1 main@45->ptr2 main@56->never_returns
  callgraph.rev_order dead_callee leaf_a g leaf_b h never_returns ptr1 ptr2 main ptr3 uncalled
  $ grep -e "call callgraph\." legacy.log candidate.log | sed -e 's/ answer=.*//'
  legacy.log:[acceptance] call callgraph.edges legacy-reads=11 resolved=0
  legacy.log:[acceptance] call callgraph.rev_order legacy-reads=0 resolved=0
  candidate.log:[acceptance] call callgraph.edges legacy-reads=0 resolved=11
  candidate.log:[acceptance] call callgraph.rev_order legacy-reads=0 resolved=0

InOut: the effects of each function, of each call, of each statement and of
expressions. Eva's final display has computed the outputs of the analyzed
functions; the driver clears InOut's memos, and asks the functions callees
first, so that each request computes its own answer from Eva's results.
The answers are those of the reference.
  $ grep -e "^inout\." candidate.answers > inout.txt
  $ grep -e "^inout\." reference.answers | diff - inout.txt
  $ for family in function callwise statement expression; do echo "$family $(grep -c -e "\"family\":\"inout-$family\"" candidate.jsonl)"; done
  function 55
  callwise 10
  statement 60
  expression 10

The sure outputs of g exclude t2, which only its second call writes; its
may outputs include it. The effects of each call tell them apart.
  $ grep -e "^inout\.\(kf_outputs\|precise\|call\)\..*\<g\>" inout.txt
  inout.kf_outputs.g a; rw; t1; t2;; __retres
  inout.precise.g inputs=[r; rw;; x] inputs-if-termination=[r; rw;; x] logic-inputs=[\nothing] may-outputs=[a; rw; t1; t2;; __retres] may-outputs-if-termination=[a; rw; t1; t2;; __retres] sure-outputs=[a; rw; t1;; __retres]
  inout.call.g@35.leaf_a inputs=[\nothing] inputs-if-termination=[\nothing] logic-inputs=[\nothing] may-outputs=[a] may-outputs-if-termination=[a] sure-outputs=[a]
  inout.call.main@43.g inputs=[r; rw;; x] inputs-if-termination=[r; rw;; x] logic-inputs=[\nothing] may-outputs=[a; rw; t1;; __retres] may-outputs-if-termination=[a; rw; t1;; __retres] sure-outputs=[a; rw; t1;; __retres]
  inout.call.main@44#2.g inputs=[r; rw;; x] inputs-if-termination=[r; rw;; x] logic-inputs=[\nothing] may-outputs=[a; rw; t1; t2;; __retres] may-outputs-if-termination=[a; rw; t1; t2;; __retres] sure-outputs=[a; rw; t1; t2;; __retres]

Paths, by the expectation of each request: legacy reads, then resolutions.
InOut records the effects of each call during the analysis, so that the
callwise requests, and the function-wise ones on the called functions, read
nothing. The other requests read Eva's results on the legacy path; the
candidate resolves each of them, without legacy read.
  $ for run in legacy candidate; do sed -n -e 's/.*"id":"inout\.[^"]*",.*"expect":"\([a-z]*\)",.*"reads":\[\(.\).*"resolved":\[\(.\).*/\1 \2 \3/p' $run.jsonl | sed -e 's/]/none/g' -e 's/{/some/g' | sort | uniq -c | sed -e "s/^ */$run /"; done
  legacy 18 none none none
  legacy 117 resolver some none
  candidate 18 none none none
  candidate 117 resolver none some

Server's variable filters: InOut registers whether each global variable is
read and written. The filters are enabled once Eva has computed its
results, which each row asks: one read of the computation state per filter
on the legacy path, one resolution in the candidate.
  $ grep -e "^server\.globals" candidate.answers > server.txt
  $ grep -e "^server\.globals" reference.answers | diff - server.txt
  $ cat server.txt
  server.globals.filters a:written b:written d:read,written nondet:read r:read rw:read,written s:read,written t1:written t2:written u:none untouched:none w:written
  $ grep -e "call server\.globals" legacy.log candidate.log | sed -e 's/ answer=.*//'
  legacy.log:[acceptance] call server.globals.filters legacy-reads=24 resolved=0
  candidate.log:[acceptance] call server.globals.filters legacy-reads=0 resolved=24

Statuses and alarms. Eva emits them from its results; they are stored apart
from its results, and reading them reads neither store. The status that Eva
emits on each property, and the consolidated status, are those of the
reference.
  $ grep -e "^status\." candidate.answers > statuses.txt
  $ grep -e "^status\." reference.answers | diff - statuses.txt
  $ cat statuses.txt
  status.L14#1 requires; u ≡ 0: eva=none consolidated=Valid
  status.L15#1 default behavior: eva=none consolidated=Valid
  status.L23#1 ensures; \result ≡ 0: eva=VALID consolidated=Valid_but_dead
  status.L24#1 default behavior: eva=none consolidated=Valid_but_dead
  status.L24#2 reachability of function never_returns: eva=**NOT** VALID consolidated=Invalid
  status.L30#1 requires; x > 0: eva=none consolidated=Valid
  status.L31#1 default behavior: eva=none consolidated=Valid
  status.L43#1 status of 'requires; x > 0' of g at stmt 44: eva=VALID consolidated=Valid
  status.L44#1 status of 'requires; x > 0' of g at stmt 46: eva=VALID consolidated=Valid
  status.L47#1 reachability of stmt plugins.i:47:5-18 in main: eva=**NOT** VALID consolidated=Invalid
  status.L47#2 status of 'requires; u ≡ 0' of dead_callee at stmt 51: eva=VALID consolidated=Valid_but_dead
  status.L48#1 assert y ≥ 0;: eva=VALID consolidated=Valid_but_dead
  status.L48#2 reachability of stmt plugins.i:48:9-23 in main: eva=**NOT** VALID consolidated=Invalid
  status.L50#1 assert y ≡ 3;: eva=VALID consolidated=Valid
  status.L53#1 assert \at(s,L) + 1 ≡ s;: eva=VALID consolidated=Valid
  status.L55#1 assert Eva: division_by_zero: d ≢ 0;: eva=unknown consolidated=Unknown

Ivette's view of the properties, with the alarms, through Server.
  $ grep -e "^server\.properties" candidate.answers > properties.txt
  $ grep -e "^server\.properties" reference.answers | diff - properties.txt
  $ sed -e 's/^server\.properties //' properties.txt | tr '|' '\n' | sed -e 's/^ *//' -e 's/ *$//'
  L14 requires - valid
  L15 behavior - valid
  L23 ensures - valid_but_dead
  L24 behavior - valid_but_dead
  L24 reachable - invalid
  L30 requires - valid
  L31 behavior - valid
  L43 instance - valid
  L44 instance - valid
  L47 instance - valid_but_dead
  L47 reachable - invalid
  L48 assert - valid_but_dead
  L48 reachable - invalid
  L50 assert - valid
  L53 assert - valid
  L55 assert division_by_zero unknown

Statistics. The coverage and the number of alarms are semantic results,
those of the reference. The statistics of the execution, such as the time,
the memory or the iterations, are recorded apart and not compared.
  $ grep -e "^statistics\." candidate.answers > statistics.txt
  $ grep -e "^statistics\." reference.answers | diff - statistics.txt
  $ cat statistics.txt
  statistics.semantic alarm-count=1 stmt-coverage=0.926829 fun-coverage=0.727273
  $ grep -e "execution-statistics" candidate.log
  [acceptance] execution-statistics memory-usage analysis-time iterations memexec-hits memexec-misses max-widenings max-unrolling partitioning-index-hits partitioning-index-misses
  $ grep -c -e '"kind":"execution-statistics"' reference.jsonl candidate.jsonl
  reference.jsonl:1
  candidate.jsonl:1
  $ grep -e "call \(status\|server\.properties\|statistics\)" legacy.log candidate.log | sed -e 's/^\([a-z]*\)\.log:.* \(legacy-reads=[^ ]* resolved=[^ ]*\) .*/\1 \2/' | sort | uniq -c | sed -e 's/^ *//'
  18 candidate legacy-reads=0 resolved=0
  18 legacy legacy-reads=0 resolved=0

The summary that Eva prints is that of the reference.
  $ for run in reference candidate; do sed -n -e '/^\[eva:summary\]/,/^\[/p' $run.log | grep -v -e "^\[acceptance\]" > $run.summary; done
  $ diff reference.summary candidate.summary
  $ grep -e "coverage" candidate.summary
    8 functions analyzed (out of 11): 73% coverage.
    In these functions, 38 statements reached (out of 41): 93% coverage.

Native comparison: the reference and the candidate run in one process, and
their answers are compared with the equality of their values: InOut's
effects with the equality of their zones, the guard outcomes and the call
predicates as booleans. The other answers are compared as text.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance plugins-native -inout-state-query-acceptance-output native.jsonl plugins.i > native.log 2>&1
  $ grep -e "native compared" native.log
  [acceptance] native compared=151 differing=0
  $ grep -c -e '"kind":"native",' native.jsonl
  194
  $ grep -c -e '"kind":"native",.*"text_equal":true' native.jsonl
  194

Annotation statuses after the analysis. Eva marks the postconditions of an
analyzed function as dead when its return statement is unreachable, as for
never_returns. On the legacy path, it reads the analysis status of each
function to tell whether its body was analyzed; the candidate tells it from
the invocations of the hit log. It then asks whether statements are
reachable, which the hit log answers. Eva then refines the statuses of the
alarms and of the assertions that use a C label, from the states of each
callstack and from the initial state of the logic, which the hit log
answers too: the candidate reads nothing.
  $ grep -e "execution phase=post-analysis reader=Eva.Eval_annots" legacy.log candidate.log
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=getter store=cvalue
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=enumeration store=cvalue
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=availability store=analysis-status
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=getter store=cvalue
  legacy.log:[acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_green_and_red access=enumeration store=cvalue

Trap. Every read of the legacy store aborts the run, in every phase, except
those of the readers that other changes migrate: the registration of the
states by the engine. The candidate runs the whole battery under the trap.
The reads left are those of the exempt reader; every request reads
nothing, and the answers are those of the reference.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance plugins-trap -inout-state-query-acceptance-output trap.jsonl plugins.i > trap.log 2>&1
  $ grep -e "guard=" -e "legacy result-store" trap.log
  [acceptance] mode=plugins-trap guard=trap-except:Eva.Engine.register_state
  $ grep -e "^\[acceptance\] execution phase=" trap.log | sed -e 's/ access=.*//' | sort -u
  [acceptance] execution phase=analysis reader=Eva.Engine.register_state
  $ grep -e "^\[acceptance\] call" trap.log | sed -e 's/^\[acceptance\] call [^ ]* \(legacy-reads=[^ ]*\) .*/\1/' | sort | uniq -c | sed -e 's/^ *//'
  194 legacy-reads=0
  $ sed -n -e 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' trap.log | diff reference.answers -

Control: on the legacy path, the trap aborts the run at the first read that
is not exempt, when the statistics of Eva ask whether a statement of the
first analyzed function is reachable.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance plugins-trap plugins.i > trap-control.log 2>&1
  [1]
  $ grep -e "legacy result-store" trap-control.log
  [eva] User Error: legacy result-store read trapped: phase=collection reader=Eva.Summary.compute_fun_stats access=availability store=analysis-status point=before line 11 of leaf_a via=Eva.Results.is_reachable
