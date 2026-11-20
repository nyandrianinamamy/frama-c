Rebuild the point states of a fresh invocation from the hit log (prototype,
see plugins/inout/prototype-state-query).

At a straight-line assignment, the request on each supplied stack is served
by the resolver, before and after the statement, without legacy read. The
unfiltered request still reads the legacy store.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate assign.i > candidate.log 2>&1
  $ grep -e "call model.before-P" -e "call model.after-P" candidate.log
  [acceptance] call model.before-P legacy-reads=2 resolved=0 answer=g ∈ {4; 9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P legacy-reads=2 resolved=0 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED

In one process, a fresh-only reference on the legacy path and the candidate
run on the same AST; their models are equal under Cvalue's native equality.
The reference reads the legacy store and resolves nothing.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance native assign.i > native.log 2>&1
  $ grep -e "native model.before-P" -e "native model.after-P" -e "native compared" native.log
  [acceptance] native model.before-P equal=true reference-reads=2 reference-resolved=0 legacy-reads=2 resolved=0
  [acceptance] native model.before-P.main/f@15 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.before-P.main/f@18 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.after-P equal=true reference-reads=2 reference-resolved=0 legacy-reads=2 resolved=0
  [acceptance] native model.after-P.main/f@15 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native model.after-P.main/f@18 equal=true reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native compared=31 differing=0

Stages of the input. The initial state holds the initialized globals; the
root call binds the formal n of main. The start of f is its input after the
binding of x, and its first statement sees the entries that survive the
precondition. No entry survives the precondition of h: its input exists,
its body is bottom.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate stages.i > stages.log 2>&1
  $ grep -e "call model.initial" -e "pos-root" -e "of-f\." -e "of-h\." -e "visits [fh]" stages.log
  [acceptance] call model.initial legacy-reads=2 resolved=0 answer=g ∈ {3}; y ∈ {0}
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
  [acceptance] native compared=25 differing=0

Collection. InOut computes the callwise inputs and outputs of each call from
the input of the invocation and the point states that Eva passes to its
hook: it reads no legacy state during the collection, and serves its answers
without legacy read. Eva's own statistics hook still reads the store.
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

Expected difference. On the legacy path, InOut reads the input of the call
from the store during the analysis, before any result is available: it
gets Top, and the logic inputs of \at(*p, Pre) are ANYTHING. From the input
of the invocation, they are a and p.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance candidate pre-label.i > pre-legacy.log 2>&1
  $ grep -e "call inout" pre-legacy.log
  [acceptance] call inout.call-f@15 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; ANYTHING(origin:Unknown)
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate pre-label.i > pre-hit-log.log 2>&1
  $ grep -e "call inout" pre-hit-log.log
  [acceptance] call inout.call-f@15 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs: a;; p

Control: a resolver that rebuilds every visit from the first producer of its
function answers the second call with the state of the first, g = 4 instead
of g = 9.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance wrong-producer assign.i > wrong-producer.log 2>&1
  $ grep -e "call model.before-P.main" wrong-producer.log
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED

With memexec, the second call to f is a hit on the entry of the first. The
resolver answers its input, recorded at the call, and declines the points of
its body, which it cannot rebuild yet: these requests read the legacy store.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -inout-state-query-acceptance candidate assign.i > memexec.log 2>&1
  $ grep -e "of-f.main/f@18" -e "visits f" memexec.log
  [acceptance] visits f.main/f@15 body#1: 1 entries survive the preconditions; input:; g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.start-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@18 legacy-reads=2 resolved=0 answer=error bottom
  [acceptance] call model.end-of-f.main/f@18 legacy-reads=2 resolved=0 answer=error bottom
  [acceptance] visits f.main/f@18 hit#1: no body analysis; input:; g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
