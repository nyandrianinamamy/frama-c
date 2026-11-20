Rebuild the point states of a fresh invocation from the hit log (prototype,
see plugins/inout/prototype-state-query).

At a straight-line assignment, the request on each supplied stack is served
by the resolver, before and after the statement, without legacy read. So is
the unfiltered request, from the states of both stacks; see
stack-selection.t for the other selections.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate assign.i > candidate.log 2>&1
  $ grep -e "call model.before-P" -e "call model.after-P" candidate.log
  [acceptance] call model.before-P legacy-reads=0 resolved=1 answer=g ∈ {4; 9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P legacy-reads=0 resolved=1 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED

In one process, a fresh-only reference on the legacy path and the candidate
run on the same AST; their models are equal under Cvalue's native equality,
and InOut's callwise results, compared for each of the two calls, have equal
zones. The reference reads the legacy store and resolves nothing.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance native assign.i > native.log 2>&1
  $ grep -e "native model.before-P" -e "native model.after-P" -e "native compared" native.log
  [acceptance] native model.before-P equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.before-P.main/f@15 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.before-P.main/f@18 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.after-P equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.after-P.main/f@15 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.after-P.main/f@18 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native compared=33 differing=0

Stages of the input. The initial state holds the initialized globals; the
root call binds the formal n of main. The start of f is its input after the
binding of x, and its first statement sees the entries that survive the
precondition. No entry survives the precondition of h: its input exists,
its body is bottom.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate stages.i > stages.log 2>&1
  $ grep -e "call model.initial" -e "pos-root" -e "of-f\." -e "of-h\." -e "visits [fh]" stages.log
  [acceptance] call model.initial legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {0}
  [acceptance] call model.initial.main legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {0}
  [acceptance] call model.before-pos-root legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {0}; n ∈ [--..--]
  [acceptance] call model.after-pos-root legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {13}; n ∈ [-2147483648..5]; v ∈ {10}; tmp ∈ {2; 10}
  [acceptance] call model.start-of-f.main/f@22 legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {0}; x ∈ {2; 10}; n ∈ [--..--]; v ∈ {2; 10}; tmp ∈ {2; 10}
  [acceptance] call model.body-entry-of-f.main/f@22 legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {0}; x ∈ {10}; n ∈ [--..--]; v ∈ {2; 10}; tmp ∈ {2; 10}
  [acceptance] call model.end-of-f.main/f@22 legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {13}; x ∈ {10}; n ∈ [--..--]; v ∈ {2; 10}; tmp ∈ {2; 10}
  [acceptance] visits f.main/f@22 body#1: 1 entries survive the preconditions; input:; g ∈ {3}; y ∈ {0}; x ∈ {2; 10}; n ∈ [--..--]; v ∈ {2; 10}; tmp ∈ {2; 10}
  [acceptance] call model.start-of-h.main/h@24 legacy-reads=0 resolved=1 answer=g ∈ {3}; y ∈ {13}; x ∈ {10}; n ∈ [6..2147483647]; v ∈ {10}; tmp ∈ {2; 10}
  [acceptance] call model.body-entry-of-h.main/h@24 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call model.end-of-h.main/h@24 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] visits h.main/h@24 body#2: no entry survives the preconditions; input:; g ∈ {3}; y ∈ {13}; x ∈ {10}; n ∈ [6..2147483647]; v ∈ {10}; tmp ∈ {2; 10}
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance native stages.i > stages-native.log 2>&1
  $ grep -e "equal=false" -e "native compared" stages-native.log
  [acceptance] native compared=27 differing=0

Collection. InOut computes the callwise inputs and outputs of each call from
the point states that Eva passes to its hook. The state at the start of the
call, which a request answers Top during the analysis, is taken without the
request: InOut reads no legacy state during the collection, and serves its
answers without legacy read. Eva's own statistics hook still reads the
store.
  $ grep -e "phase=collection" candidate.log
  [acceptance] execution phase=collection reader=Eva.Summary.compute_fun_stats access=availability store=analysis-status
  $ grep -e "call inout" candidate.log
  [acceptance] call inout.call-f@15 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call inout.call-f@18 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing

Control: on the legacy path (-eva-no-hit-log), the resolver serves nothing
and InOut reads the input of each call from the legacy store during the
collection.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance candidate assign.i > legacy-path.log 2>&1
  $ grep -e "phase=collection" -e "call model.before-P" legacy-path.log
  [acceptance] execution phase=collection reader=Eva.Summary.compute_fun_stats access=availability store=analysis-status
  [acceptance] execution phase=collection reader=Eva.Results.get_cvalue_model access=availability store=analysis-status
  [acceptance] call model.before-P legacy-reads=2 resolved=0 answer=g ∈ {4; 9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@15 legacy-reads=2 resolved=0 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=2 resolved=0 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED

The Pre label of InOut. Callwise InOut runs in the collection hook, during
the analysis, when a request on the stored results answers Top. On the
legacy path, InOut makes this request for the input of each call, and the
logic inputs of \at(*p, Pre) are ANYTHING. The input of each call has
p ∈ {&a; &b}, and the precondition of f reduces it to &a: the logic inputs
would be a; b; p from the input, and a; p from the entry that survives.
Memexec does not cache a call whose logic inputs are ANYTHING: f is called
twice with the same input, and its body is analyzed twice.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -eva-msg-key progress -eva-no-hit-log -inout-state-query-acceptance candidate pre-label.i > pre-legacy.log 2>&1
  $ grep -e "computing for function f" -e "Reusing" -e "phase=collection reader=Eva.Results" pre-legacy.log
    computing for function f <- main.
    computing for function f <- main.
  [acceptance] execution phase=collection reader=Eva.Results.get_cvalue_model access=availability store=analysis-status
  $ grep -e "call inout" pre-legacy.log > inout-legacy.txt
  $ cat inout-legacy.txt
  [acceptance] call inout.call-f@19 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; ANYTHING(origin:Unknown)
  [acceptance] call inout.call-f@21 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; ANYTHING(origin:Unknown)

With the hit log, InOut takes the same answer without reading the store.
Its answers are those of the legacy path, and both calls analyze the body:
the hit log records two body visits and no hit.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -eva-msg-key progress -inout-state-query-acceptance candidate pre-label.i > pre-hit-log.log 2>&1
  $ grep -e "computing for function f" -e "Reusing" -e "phase=collection reader=Eva.Results" -e "visits f" pre-hit-log.log
    computing for function f <- main.
    computing for function f <- main.
  [acceptance] visits f.main/f@19 body#1: 1 entries survive the preconditions; input:; a ∈ {1}; b ∈ {0}; p ∈ {{ &a ; &b }}; y ∈ {0}; x ∈ {10}; n ∈ [--..--]; t[0] ∈ {{ &a }}; [1] ∈ {{ &b }}
  [acceptance] visits f.main/f@21 body#2: 1 entries survive the preconditions; input:; a ∈ {1}; b ∈ {0}; p ∈ {{ &a ; &b }}; y ∈ {10}; x ∈ {10}; n ∈ [--..--]; t[0] ∈ {{ &a }}; [1] ∈ {{ &b }}
  $ grep -e "call inout" pre-hit-log.log > inout-hit-log.txt
  $ diff inout-legacy.txt inout-hit-log.txt

In one process, without memexec, InOut's callwise results of the fresh-only
reference and of the candidate have equal zones, the logic inputs included.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance native pre-label.i > pre-native.log 2>&1
  $ grep -e "native inout" -e "equal=false" -e "native compared" pre-native.log
  [acceptance] native inout.call-f@19 equal=true reference-reads=0 reference-resolved=0 legacy-reads=0 resolved=0
  [acceptance] native inout.call-f@21 equal=true reference-reads=0 reference-resolved=0 legacy-reads=0 resolved=0
  [acceptance] native compared=39 differing=0

The hit log records nothing when another domain than cvalue runs, even
with -eva-hit-log. InOut then reads the store as on the legacy path, with
the same answers and the same analyses of f.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue,equality -eva-memexec -eva-msg-key progress -inout-state-query-acceptance candidate pre-label.i > pre-equality.log 2>&1
  $ grep -e "config" -e "computing for function f" -e "Reusing" -e "phase=collection reader=Eva.Results" -e "visits f" pre-equality.log
  [acceptance] config -eva-domains=cvalue,equality -eva-slevel=0 -eva-memexec=true -eva-hit-log=true -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
    computing for function f <- main.
    computing for function f <- main.
  [acceptance] execution phase=collection reader=Eva.Results.get_cvalue_model access=availability store=analysis-status
  $ grep -e "call inout" pre-equality.log > inout-equality.txt
  $ diff inout-legacy.txt inout-equality.txt

Memexec admission with a precondition. The precondition of f reads z and g,
which its body does not read, and memexec does not compare them. On the
legacy path and with the hit log, the second call to f reuses the first,
and InOut's answers are the same. The hit log records the input of each
call before the precondition reduces it; no entry of the third call
survives.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -eva-msg-key progress -eva-no-hit-log -inout-state-query-acceptance candidate precondition.i > precondition-legacy.log 2>&1
  $ grep -e "computing for function f" -e "Reusing" precondition-legacy.log
    computing for function f <- main.
  [eva:progress] precondition.i:24: Reusing old results for call to f
    computing for function f <- main.
  $ grep -e "call inout" precondition-legacy.log > precondition-inout-legacy.txt
  $ cat precondition-inout-legacy.txt
  [acceptance] call inout.call-f@20 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call inout.call-f@24 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call inout.call-f@26 legacy-reads=0 resolved=0 answer=Operational inputs:; \nothing; Operational inputs on termination:; \nothing; Sure outputs:; ANYTHING(origin:Unknown); Over outputs:; \nothing; Over outputs on termination:; \nothing; Logic inputs:; \nothing
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -eva-msg-key progress -inout-state-query-acceptance candidate precondition.i > precondition-hit-log.log 2>&1
  $ grep -e "computing for function f" -e "Reusing" -e "visits f" precondition-hit-log.log
    computing for function f <- main.
  [eva:progress] precondition.i:24: Reusing old results for call to f
    computing for function f <- main.
  [acceptance] visits f.main/f@20 body#1: 1 entries survive the preconditions; input:; g ∈ {9}; z ∈ [--..--]; y ∈ {0}; x ∈ {10}; n ∈ [--..--]
  [acceptance] visits f.main/f@24 hit#1: no body analysis; input:; g ∈ {4}; z ∈ [--..--]; y ∈ {0}; x ∈ {10}; n ∈ [--..--]
  [acceptance] visits f.main/f@26 body#2: no entry survives the preconditions; input:; g ∈ {4}; z ∈ {1}; y ∈ {11}; x ∈ {11}; n ∈ [--..--]
  $ grep -e "call inout" precondition-hit-log.log > precondition-inout-hit-log.txt
  $ diff precondition-inout-legacy.txt precondition-inout-hit-log.txt

Control: a resolver that rebuilds every visit from the first producer of its
function answers the second call with the state of the first, g = 4 instead
of g = 9.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance wrong-producer assign.i > wrong-producer.log 2>&1
  $ grep -e "call model.before-P.main" wrong-producer.log
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED

With memexec, the first call to f is analyzed: the resolver serves the
points of its body as without memexec. The second call is a hit on the entry
of the first. The resolver answers its input, recorded at the call, and
declines the points of its body, which it cannot rebuild yet: these requests
read the legacy store.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -inout-state-query-acceptance candidate assign.i > memexec.log 2>&1
  $ grep -e "model.before-P.main" -e "model.after-P.main" -e "of-f.main" -e "visits f" memexec.log
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.start-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@15 body#1: 1 entries survive the preconditions; input:; g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.start-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@18 legacy-reads=2 resolved=0 answer=error bottom
  [acceptance] call model.end-of-f.main/f@18 legacy-reads=2 resolved=0 answer=error bottom
  [acceptance] visits f.main/f@18 hit#1: no body analysis; input:; g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED

Without saved results for f (-eva-no-results-function f), the resolver
answers the input of each call, and Top at the points of its body, as the
legacy store does. The native comparison agrees.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-results-function f -inout-state-query-acceptance candidate assign.i > no-results.log 2>&1
  $ grep -e "of-f.main" no-results.log
  [acceptance] call model.start-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@15 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call model.end-of-f.main/f@15 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call model.start-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@18 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call model.end-of-f.main/f@18 legacy-reads=0 resolved=1 answer=error top
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-results-function f -inout-state-query-acceptance native assign.i > no-results-native.log 2>&1
  $ grep -e "equal=false" -e "native compared" no-results-native.log
  [acceptance] native compared=21 differing=0

The cvalue domain prints the final states of each function from the
consolidated states before its first and return statements. f is recursive
and only partially analyzed; the hit log answers the marking of unreachable
statements without consolidating these states, which the engine then
consolidates itself. The final states of f are printed as on the legacy
path.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva recursive.i > recursive.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva -eva-no-hit-log recursive.i > recursive-legacy.log 2>&1
  $ grep -A2 "Values at end of function f" recursive.log
  [eva:final-states] Values at end of function f:
    x ∈ [--..--]
    __retres ∈ [-2147483647..2147483647]
  $ grep -e "final-states" -e "^  " recursive.log > final.txt
  $ grep -e "final-states" -e "^  " recursive-legacy.log > final-legacy.txt
  $ diff final-legacy.txt final.txt
