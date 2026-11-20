Distinguish unreachable points from unavailable results (prototype, see
plugins/inout/prototype-state-query).

The reach- modes of the acceptance driver make requests on every labelled
statement and every function of the input file, on each callstack that the
call hooks of Eva see during the analysis, which do not depend on the
result store: the model before and after the statement on each callstack
and without callstack, Eva.Results.is_reachable, is_reachable_pos and
is_empty, the callstacks at the point, Eva.Analysis.status and
Eva.Results.are_available. The reference runs Eva on the legacy path,
without the hit log; the candidate runs it with the hit log. A line
"internal" gives, for each callstack, the answer of the hit log before its
public conversion.

  $ answers () { sed -n 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' "$1"; }
  $ run () { mode=$1; log=$2; shift 2; frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance "$mode" "$@" > "$log" 2>&1; }

The migrated readers are the requests on one callstack, is_reachable,
is_reachable_pos and is_empty. In every candidate below, the hit log
serves each of them without legacy read; served lists the others.
  $ served () { grep -E "call (reach|fn)\.[^ ]+\.(reachable|empty-before|empty-after|(before|after|reachable-pos|empty|start)\.[^ ]+) " "$1" | awk '!/legacy-reads=0 resolved=1 /{n++} END{print n+0}'; }

Complete analysis. f reaches P and never U; spin does not terminate, so C is
reached and its successor D is not, nor is N after the loop of spin. by_spec
is interpreted by its specification (-eva-use-spec), floor by its builtin:
their calls are reached, and the hit log tells that their bodies are not
analyzed. The public answer stays Bottom, as Eva.Analysis.status declares
it for both. The candidate gives the reference's answers.
  $ run reach-reference points-reference.log points.i -eva-use-spec by_spec
  $ run reach-candidate points.log points.i -eva-use-spec by_spec
  $ answers points-reference.log > points-reference.txt
  $ answers points.log > points.txt
  $ diff points-reference.txt points.txt
  $ served points.log
  0
  $ grep -e "internal" points.log
  [acceptance] internal S.main/by_spec@40 before=body not analyzed after=body not analyzed
  [acceptance] internal B.main/floor@41 before=body not analyzed after=body not analyzed
  [acceptance] internal N.main/spin@44 before=unreachable after=unreachable
  [acceptance] internal U.main/f@38 before=unreachable after=unreachable
  [acceptance] internal U.main/f@39 before=unreachable after=unreachable
  [acceptance] internal P.main/f@38 before=reached after=reached
  [acceptance] internal P.main/f@39 before=reached after=reached
  [acceptance] internal C.main before=reached after=unreachable
  [acceptance] internal D.main before=unreachable after=unreachable
  $ grep -e "call fn\.\(by_spec\|floor\|spin\)\.\(status\|start\)" points.log
  [acceptance] call fn.by_spec.status legacy-reads=1 resolved=0 answer=specification used
  [acceptance] call fn.by_spec.start.main/by_spec@40 legacy-reads=0 resolved=1 answer=nondet ∈ [--..--]; g ∈ {2}; h ∈ {0}; x ∈ {3}; r ∈ UNINITIALIZED; d ∈ UNINITIALIZED; __retres ∈ UNINITIALIZED
  [acceptance] call fn.floor.status legacy-reads=1 resolved=0 answer=builtin floor
  [acceptance] call fn.floor.start.main/floor@41 legacy-reads=0 resolved=1 answer=nondet ∈ [--..--]; g ∈ {2}; h ∈ {0}; x ∈ {2.5}; r ∈ {4}; d ∈ UNINITIALIZED; __retres ∈ UNINITIALIZED
  [acceptance] call fn.spin.status legacy-reads=1 resolved=0 answer=analyzed complete
  [acceptance] call fn.spin.start.main/spin@44 legacy-reads=0 resolved=1 answer=nondet ∈ [--..--]; g ∈ {2}; h ∈ {0}; r ∈ {4}; d ∈ {2.}; __retres ∈ UNINITIALIZED
  $ grep -e "call reach\.[SBNCD]\.\(reachable\|empty-before\|before\.\|after\.\)" points.log
  [acceptance] call reach.S.reachable legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.S.empty-before legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.S.before.main/by_spec@40 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.S.after.main/by_spec@40 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.S.reachable-pos.main/by_spec@40 legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.B.reachable legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.B.empty-before legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.B.before.main/floor@41 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.B.after.main/floor@41 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.B.reachable-pos.main/floor@41 legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.N.reachable legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.N.empty-before legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.N.before.main/spin@44 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.N.after.main/spin@44 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.N.reachable-pos.main/spin@44 legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.C.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.C.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.C.before.main legacy-reads=0 resolved=1 answer=nondet ∈ [--..--]; g ∈ {2}; h ∈ {0}; r ∈ {4}; d ∈ {2.}; __retres ∈ UNINITIALIZED
  [acceptance] call reach.C.after.main legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.C.reachable-pos.main legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.D.reachable legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.D.empty-before legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.D.before.main legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.D.after.main legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.D.reachable-pos.main legacy-reads=0 resolved=1 answer=false

A missing state establishes deadness only in a complete analysis, for a
visit that analyzed its body to completion with its points recorded.

Interrupted analysis. The driver stops the analysis when the second call
to f calls stop_analysis. The first call to f completed and reached R; the
second one stopped before R, and nothing after it was analyzed. The legacy
store has no state at R on the second callstack nor at L, and answers
Bottom: R and L look unreachable. The hit log answers that these results
are unavailable, which the public requests convert to Top: this is the
deliberate correction of an ambiguous legacy conversion. Each model on one
callstack that the native comparison finds different is one of them.
  $ run reach-reference interrupted-reference.log interrupted.i
  $ run reach-candidate interrupted.log interrupted.i
  $ answers interrupted-reference.log > interrupted-reference.txt
  $ answers interrupted.log > interrupted.txt
  $ diff interrupted-reference.txt interrupted.txt
  21,24c21,24
  < reach.R.before.main/f@19 error bottom
  < reach.R.after.main/f@19 error bottom
  < reach.R.reachable-pos.main/f@19 false
  < reach.R.empty.main/f@19 true
  ---
  > reach.R.before.main/f@19 error top
  > reach.R.after.main/f@19 error top
  > reach.R.reachable-pos.main/f@19 true
  > reach.R.empty.main/f@19 false
  26,28c26,28
  < reach.L.reachable false
  < reach.L.empty-before true
  < reach.L.empty-after true
  ---
  > reach.L.reachable true
  > reach.L.empty-before false
  > reach.L.empty-after false
  32,35c32,35
  < reach.L.before.main error bottom
  < reach.L.after.main error bottom
  < reach.L.reachable-pos.main false
  < reach.L.empty.main true
  ---
  > reach.L.before.main error top
  > reach.L.after.main error top
  > reach.L.reachable-pos.main true
  > reach.L.empty.main false
  [1]
  $ served interrupted.log
  0
  $ grep -e "internal" -e "stop requested" interrupted.log
  [acceptance] stop requested at main/f@19/stop_analysis@11
  [acceptance] internal R.main/f@18 before=reached after=reached
  [acceptance] internal R.main/f@19 before=unavailable (interrupted) after=unavailable (interrupted)
  [acceptance] internal L.main before=unavailable (interrupted) after=unavailable (interrupted)
  $ run reach-native interrupted-native.log interrupted.i
  $ grep -e "equal=false" -e "native compared" interrupted-native.log
  [acceptance] native reach.R.before.main/f@19 equal=false reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.R.after.main/f@19 equal=false reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.L.before.main equal=false reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.L.after.main equal=false reference-reads=2 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native compared=12 differing=4

Not corrected: Eva.Analysis.status answers analyzed complete after an
interrupted analysis, although its documentation says partial; the model
without callstack still reads the legacy store, and is Bottom at L and the
state of the first call alone at R.
  $ grep -e "call fn\.f\.status" -e "call reach\.[RL]\.model-before" interrupted.log
  [acceptance] call fn.f.status legacy-reads=1 resolved=0 answer=analyzed complete
  [acceptance] call reach.R.model-before legacy-reads=4 resolved=0 answer=g ∈ {0}; x ∈ {1}
  [acceptance] call reach.L.model-before legacy-reads=3 resolved=0 answer=error bottom

Results that are not recorded. With -eva-no-results-function f, the
states of f are not recorded; with -eva-no-results-domain cvalue or
-eva-no-results, no state is. The legacy is_empty answers true wherever no
state is recorded, so that P, which f reaches, and even C in main look
unreachable. The hit log tells that these results are unavailable, and
is_empty answers false: this is the only difference with the reference.
The other requests give the legacy answers: Top on one callstack, a top
model without callstack, reachable, and no callstack.
  $ run reach-reference nrf-reference.log points.i -eva-use-spec by_spec -eva-no-results-function f
  $ run reach-candidate nrf.log points.i -eva-use-spec by_spec -eva-no-results-function f
  $ answers nrf-reference.log > nrf-reference.txt
  $ answers nrf.log > nrf.txt
  $ diff nrf-reference.txt nrf.txt
  57,58c57,58
  < reach.U.empty-before true
  < reach.U.empty-after true
  ---
  > reach.U.empty-before false
  > reach.U.empty-after false
  65c65
  < reach.U.empty.main/f@38 true
  ---
  > reach.U.empty.main/f@38 false
  69c69
  < reach.U.empty.main/f@39 true
  ---
  > reach.U.empty.main/f@39 false
  72,73c72,73
  < reach.P.empty-before true
  < reach.P.empty-after true
  ---
  > reach.P.empty-before false
  > reach.P.empty-after false
  80c80
  < reach.P.empty.main/f@38 true
  ---
  > reach.P.empty.main/f@38 false
  84c84
  < reach.P.empty.main/f@39 true
  ---
  > reach.P.empty.main/f@39 false
  [1]
  $ served nrf.log
  0
  $ grep -e "internal [UP]\." nrf.log
  [acceptance] internal U.main/f@38 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal U.main/f@39 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal P.main/f@38 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal P.main/f@39 before=unavailable (not recorded) after=unavailable (not recorded)
  $ grep -e "call fn\.f\.\(status\|available\)" -e "call reach\.P\.\(stacks\|reachable\|model-before\|before\.\)" nrf.log
  [acceptance] call fn.f.status legacy-reads=1 resolved=0 answer=analyzed without results
  [acceptance] call fn.f.available legacy-reads=1 resolved=0 answer=false
  [acceptance] call reach.P.stacks legacy-reads=0 resolved=1 answer=
  [acceptance] call reach.P.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.P.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] call reach.P.before.main/f@38 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call reach.P.reachable-pos.main/f@38 legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.P.before.main/f@39 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call reach.P.reachable-pos.main/f@39 legacy-reads=0 resolved=1 answer=true

  $ run reach-reference nrd-reference.log points.i -eva-use-spec by_spec -eva-no-results-domain cvalue
  $ run reach-candidate nrd.log points.i -eva-use-spec by_spec -eva-no-results-domain cvalue
  $ answers nrd-reference.log > nrd-reference.txt
  $ answers nrd.log > nrd.txt
  $ diff nrd-reference.txt nrd.txt > nrd.diff
  [1]
  $ grep -c -e "^<" nrd.diff
  17
  $ grep -c -e "^< reach\.[^ ]*\.empty[^ ]* true$" nrd.diff
  17
  $ sed -n 's/^> //p' nrd.diff
  reach.N.empty-before false
  reach.N.empty-after false
  reach.N.empty.main/spin@44 false
  reach.U.empty-before false
  reach.U.empty-after false
  reach.U.empty.main/f@38 false
  reach.U.empty.main/f@39 false
  reach.P.empty-before false
  reach.P.empty-after false
  reach.P.empty.main/f@38 false
  reach.P.empty.main/f@39 false
  reach.C.empty-before false
  reach.C.empty-after false
  reach.C.empty.main false
  reach.D.empty-before false
  reach.D.empty-after false
  reach.D.empty.main false
  $ served nrd.log
  0
  $ grep -e "internal" nrd.log
  [acceptance] internal S.main/by_spec@40 before=body not analyzed after=body not analyzed
  [acceptance] internal B.main/floor@41 before=body not analyzed after=body not analyzed
  [acceptance] internal N.main/spin@44 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal U.main/f@38 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal U.main/f@39 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal P.main/f@38 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal P.main/f@39 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal C.main before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal D.main before=unavailable (not recorded) after=unavailable (not recorded)
  $ grep -e "call fn\.f\.\(status\|available\|start\)" -e "call reach\.C\.\(stacks\|reachable\|empty-before\|model-before\|before\.\)" nrd.log
  [acceptance] call fn.f.status legacy-reads=1 resolved=0 answer=analyzed complete
  [acceptance] call fn.f.available legacy-reads=1 resolved=0 answer=true
  [acceptance] call fn.f.start.main/f@38 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call fn.f.start.main/f@39 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call reach.C.stacks legacy-reads=2 resolved=0 answer=
  [acceptance] call reach.C.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.C.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.C.model-before legacy-reads=2 resolved=0 answer=NO INFORMATION
  [acceptance] call reach.C.before.main legacy-reads=0 resolved=1 answer=error top
  [acceptance] call reach.C.reachable-pos.main legacy-reads=0 resolved=1 answer=true

Not corrected: with -eva-no-results-domain cvalue, Eva.Analysis.status
answers analyzed complete and Eva.Results.are_available true, while no
state of f is available.

  $ run reach-reference nr-reference.log points.i -eva-use-spec by_spec -eva-no-results
  $ run reach-candidate nr.log points.i -eva-use-spec by_spec -eva-no-results
  $ answers nr-reference.log > nr-reference.txt
  $ answers nr.log > nr.txt
  $ diff nr-reference.txt nr.txt > nr.diff
  [1]
  $ diff nrd.diff nr.diff
  $ served nr.log
  0
  $ grep -e "call fn\.f\.\(status\|available\)" nr.log
  [acceptance] call fn.f.status legacy-reads=1 resolved=0 answer=analyzed without results
  [acceptance] call fn.f.available legacy-reads=1 resolved=0 answer=false

Pending results. While the analysis runs, f calls pending_probe, and the
driver makes requests on the callstack of f. No result is available yet:
the hit log answers that they are pending. The legacy is_empty answers
true at P; the candidate answers false. The other answers are the legacy
ones: Top on the callstack, reachable, Eva.Analysis.status partial and no
result available.
  $ run reach-reference pending-reference.log pending.i
  $ run reach-candidate pending.log pending.i
  $ answers pending-reference.log > pending-reference.txt
  $ answers pending.log > pending.txt
  $ diff pending-reference.txt pending.txt
  2c2
  < pending.P.empty-before true
  ---
  > pending.P.empty-before false
  [1]
  $ grep -e "call pending\." pending.log
  [acceptance] call pending.P.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call pending.P.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call pending.P.before.main/f@16 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call pending.fn.f.status legacy-reads=1 resolved=0 answer=analyzed partial
  [acceptance] call pending.fn.f.available legacy-reads=1 resolved=0 answer=false

Partial results of a recursion. rec is unrolled once: its first call
analyzes the body, and the recursive call uses the specification.
Eva.Analysis.status answers partial. On the callstack of the recursive
call, the hit log tells that the body is not analyzed; the public answer is
Bottom, as on the legacy path.
  $ run reach-reference recursion-reference.log recursion.i -eva-unroll-recursive-calls 1
  $ run reach-candidate recursion.log recursion.i -eva-unroll-recursive-calls 1
  $ answers recursion-reference.log > recursion-reference.txt
  $ answers recursion.log > recursion.txt
  $ diff recursion-reference.txt recursion.txt
  $ served recursion.log
  0
  $ grep -e "internal" -e "call fn\.rec\.status" -e "call reach\.R\.\(before\|reachable-pos\)\." recursion.log
  [acceptance] call fn.rec.status legacy-reads=1 resolved=0 answer=analyzed partial
  [acceptance] internal R.main/rec@15 before=reached after=reached
  [acceptance] call reach.R.before.main/rec@15 legacy-reads=0 resolved=1 answer=g ∈ [--..--]; n ∈ {2}
  [acceptance] call reach.R.reachable-pos.main/rec@15 legacy-reads=0 resolved=1 answer=true
  [acceptance] internal R.main/rec@15/rec@9 before=body not analyzed after=body not analyzed
  [acceptance] call reach.R.before.main/rec@15/rec@9 legacy-reads=0 resolved=1 answer=error bottom
  [acceptance] call reach.R.reachable-pos.main/rec@15/rec@9 legacy-reads=0 resolved=1 answer=false

A known top model. The driver starts the analysis of top.i from a top
state. T is reached, with a top model: on its callstack, the request
answers this model, while an unavailable result answers Top above. The
supplied top state reads nothing. Without callstack, the legacy conversion
gives a top model both for this known model and for an unavailable result.
The supplied state has no callstack: is_empty answers true, as on the
legacy path.
  $ run reach-reference top-reference.log top.i
  $ run reach-candidate top.log top.i
  $ answers top-reference.log > top-reference.txt
  $ answers top.log > top.txt
  $ diff top-reference.txt top.txt
  $ grep -e "internal" -e "call reach\.T\.\(model-before\|before\.\)" -e "call supplied-top" top.log
  [acceptance] call reach.T.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] internal T.main before=reached after=reached
  [acceptance] call reach.T.before.main legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] call supplied-top.model legacy-reads=0 resolved=0 answer=NO INFORMATION
  [acceptance] call supplied-top.empty legacy-reads=0 resolved=0 answer=true
  $ grep -e "call reach\.U\.model-before" nrf.log
  [acceptance] call reach.U.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION

Disabled domains. The equality and taint domains are not enabled: requests
on them answer their declared error, at reached, unreachable and
unavailable points alike, without legacy read nor resolution.
  $ cat points.log interrupted.log nrf.log nrd.log nr.log top.log > all.log
  $ grep -c -e "call reach\.[^ ]*\.\(equality\|taint\) " all.log
  62
  $ grep -c -e "call reach\.[^ ]*\.\(equality\|taint\) legacy-reads=0 resolved=0 answer=error disabled domain" all.log
  62

Final states. Eva's display of the final states reads the consolidated
state before the first and the return statements. The post-analysis does
not store it for a partial analysis, such as the recursion of rec, nor for
any function without -eva-join-results. The legacy is_reachable stored it
as a side effect, before the display. The hit log answers is_reachable
without storing; the engine now consolidates the states before the
statements of every analyzed function, and the display prints the final
states of both functions.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec recursion.i -eva -eva-unroll-recursive-calls 1 -eva-no-join-results > final.log 2>&1
  $ grep -A1 -e "Values at end of function" final.log
  [eva:final-states] Values at end of function rec:
    g ∈ {2}
  [eva:final-states] Values at end of function main:
    g ∈ {2}
