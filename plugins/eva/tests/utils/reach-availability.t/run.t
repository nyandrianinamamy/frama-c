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

  $ answers () { sed -n 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' "$1" | grep -v -e '^select\.' -e '^pending\.select\.' | sed 's/ $//'; }
  $ run () { mode=$1; log=$2; shift 2; frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance "$mode" "$@" > "$log" 2>&1; }

The migrated readers are the requests on one callstack, is_reachable,
is_reachable_pos and is_empty. In every candidate below, the hit log
serves each of them without legacy read; served lists the others.
  $ served () { grep -E "call (reach|fn)\.[^ ]+\.(reachable|empty-before|empty-after|(before|after|reachable-pos|empty|start)\.[^ ]+) " "$1" | awk '!/legacy-reads=0 resolved=1 /{n++} END{print n+0}'; }

The driver also makes requests at each labelled statement under several
selections of the callstacks that the hooks saw for its function:
unfiltered, all of them by a selector (selector-all) and by a predicate
(filter-all), each one alone by a predicate (only:), all but one by a
selector and by a predicate (selector-without:, filter-without:), each
one by a selector with a predicate that rejects it (rejected:), all of
them by a selector with a predicate that drops one
(selector-all-filter-without:), all of them by a selector with a
predicate that rejects each one (selector-all-filter-none), all but one
by a selector with a predicate that keeps only that one
(selector-without-filter-only:), and none, by an empty selector
(selector-none) and by a predicate (filter-none). Under each, it
records the callstacks in the order of the answer, the subrequests of
by_callstack with their models, the model and is_empty. The pending probe
makes the same requests during the analysis. selections lists these
answers; selected counts those that read the legacy store or are not
resolved; inconsistent lists the selections whose model is Bottom while
is_empty is false, or the reverse, and consistent counts them.
  $ selections () { sed -n 's/^\[acceptance\] call \([^ ]*\) legacy-reads=[^ ]* resolved=[^ ]* answer=/\1 /p' "$1" | grep -e '^select\.' -e '^pending\.select\.' | sed 's/ $//'; }
  $ selected () { grep -E "call (pending\.)?select\." "$1" | awk '!/legacy-reads=0 resolved=[1-9]/{n++} END{print n+0}'; }
  $ inconsistent () { sed -n 's/^\[acceptance\] call \(\(pending\.\)\{0,1\}select\.[^ ]*\)\.\(model\|empty\) legacy-reads=[^ ]* resolved=[^ ]* answer=\(.*\)$/\1 \3 \4/p' "$1" | awk '$2 == "model" { bottom[$1] = ($3 " " $4 == "error bottom") } $2 == "empty" { empty[$1] = ($3 == "true") } END { for (k in bottom) if (bottom[k] != empty[k]) print k }' | sort; }
  $ consistent () { inconsistent "$1" | awk 'END { print NR }'; }

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
  $ selections points-reference.log > points-reference.sel
  $ selections points.log > points.sel
  $ diff points-reference.sel points.sel
  $ selected points.log
  0
  $ consistent points.log
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
  [acceptance] call fn.by_spec.status legacy-reads=0 resolved=1 answer=specification used
  [acceptance] call fn.by_spec.start.main/by_spec@40 legacy-reads=0 resolved=1 answer=nondet ∈ [--..--]; g ∈ {2}; h ∈ {0}; x ∈ {3}; r ∈ UNINITIALIZED; d ∈ UNINITIALIZED; __retres ∈ UNINITIALIZED
  [acceptance] call fn.floor.status legacy-reads=0 resolved=1 answer=builtin floor
  [acceptance] call fn.floor.start.main/floor@41 legacy-reads=0 resolved=1 answer=nondet ∈ [--..--]; g ∈ {2}; h ∈ {0}; x ∈ {2.5}; r ∈ {4}; d ∈ UNINITIALIZED; __retres ∈ UNINITIALIZED
  [acceptance] call fn.spin.status legacy-reads=0 resolved=1 answer=analyzed complete
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
callstack that the native comparison finds different is one of them. The
callstacks at R are those of the reference: the first call reached R.
  $ run reach-reference interrupted-reference.log interrupted.i
  $ run reach-candidate interrupted.log interrupted.i
  $ answers interrupted-reference.log > interrupted-reference.txt
  $ answers interrupted.log > interrupted.txt
  $ diff interrupted-reference.txt interrupted.txt
  14c14
  < reach.R.model-before g ∈ {0}; x ∈ {1}
  ---
  > reach.R.model-before NO INFORMATION
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
  26,29c26,29
  < reach.L.reachable false
  < reach.L.empty-before true
  < reach.L.empty-after true
  < reach.L.model-before error bottom
  ---
  > reach.L.reachable true
  > reach.L.empty-before false
  > reach.L.empty-after false
  > reach.L.model-before NO INFORMATION
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
  $ grep -e "equal=false" interrupted-native.log > interrupted-native.txt
  $ grep -v -e "native select\." interrupted-native.txt
  [acceptance] native reach.R.model-before equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.R.before.main/f@19 equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.R.after.main/f@19 equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.L.model-before equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.L.before.main equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native reach.L.after.main equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1

Without callstack, the legacy store answers Bottom at L, and the state of
the first call alone at R. The hit log answers Top at both: the state on
the second callstack is unavailable at R, and no callstack reaches L. The
enumeration is apart from the state: it lists the callstack of the first
call at R, whose visit reached it, and none at L.
Not corrected: Eva.Analysis.status answers analyzed complete after an
interrupted analysis, although its documentation says partial.
  $ grep -e "call fn\.f\.status" -e "call reach\.[RL]\.\(model-before\|stacks\)" interrupted.log
  [acceptance] call fn.f.status legacy-reads=0 resolved=1 answer=analyzed complete
  [acceptance] call reach.R.stacks legacy-reads=0 resolved=1 answer=main/f@18
  [acceptance] call reach.R.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] call reach.L.stacks legacy-reads=0 resolved=1 answer=
  [acceptance] call reach.L.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION

Interrupted analysis with memexec. The second call to h is a memexec hit
on the first; the second call to f then stops the analysis, after R, and
later is never entered. The legacy store has no state at Z nor at L, and
answers that they are unreachable. The hit log answers that the analysis
could still reach them: Z is not dead although no callstack of later is
recorded. At Z and L, which no recorded callstack reaches, the requests on
several callstacks or none answer Top. At R, which both calls to f
reached, they read the legacy store, as in any analysis with a memexec
hit: the callstacks below a hit are not recorded. Memexec hits are outside
the trapped configuration: this run logs the reads without trapping them.
  $ run reach-reference hit-reference.log interrupted-hit.i -eva-memexec
  $ run reach-record hit.log interrupted-hit.i -eva-memexec
  $ answers hit-reference.log > hit-reference.txt
  $ answers hit.log > hit.txt
  $ diff hit-reference.txt hit.txt
  34,37c34,37
  < reach.Z.reachable false
  < reach.Z.empty-before true
  < reach.Z.empty-after true
  < reach.Z.model-before error bottom
  ---
  > reach.Z.reachable true
  > reach.Z.empty-before false
  > reach.Z.empty-after false
  > reach.Z.model-before NO INFORMATION
  41,44c41,44
  < reach.L.reachable false
  < reach.L.empty-before true
  < reach.L.empty-after true
  < reach.L.model-before error bottom
  ---
  > reach.L.reachable true
  > reach.L.empty-before false
  > reach.L.empty-after false
  > reach.L.model-before NO INFORMATION
  47,50c47,50
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
  $ served hit.log
  0
  $ grep -e "call reach\.[RZL]\.\(stacks\|reachable\|empty-before\|model-before\) " hit.log
  [acceptance] call reach.R.stacks legacy-reads=5 resolved=0 answer=main/f@25 main/f@26
  [acceptance] call reach.R.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.R.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.R.model-before legacy-reads=6 resolved=0 answer=g ∈ {1}; x ∈ {0; 1}; n ∈ {1; 2}
  [acceptance] call reach.Z.stacks legacy-reads=0 resolved=1 answer=
  [acceptance] call reach.Z.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.Z.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.Z.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] call reach.L.stacks legacy-reads=0 resolved=1 answer=
  [acceptance] call reach.L.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.L.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.L.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION

At R, the selections on several callstacks or by a predicate that keep a
callstack of f read the legacy store as well (#81), and give the answers
of the reference; a selector that names one callstack is served by the
hit log. The selections that keep no callstack are served by the hit log.
Those that name their callstacks are empty, as in the reference: Bottom,
and is_empty true. filter-none, which does not name them, answers Top and
is_empty false. At Z and L, every selection answers Top, except those
that name their callstacks and keep none of them; at Z, which no hook
saw, selector-all names none.
  $ selections hit-reference.log > hit-reference.sel
  $ selections hit.log > hit.sel
  $ diff hit-reference.sel hit.sel > hit-sel.diff
  [1]
  $ sed -n 's/^> \(select\.R\.\)/\1/p' hit-sel.diff
  select.R.filter-none.model error top
  select.R.filter-none.empty false
  $ grep -e "^select\.[ZL]\.[^ ]*\.model error bottom" hit.sel
  select.Z.selector-all.model error bottom
  select.Z.selector-none.model error bottom
  select.L.rejected:main.model error bottom
  select.L.selector-none.model error bottom
  $ selected hit.log
  27

Selections after an interruption. The enumeration of callstacks is apart
from the state: callstacks and by_callstack list each selected callstack
with a visit that reaches the point, in the order of the legacy store,
even when the state of another visit, or of another selected callstack,
is unavailable. The model of a selection is known only when the state of
each selected callstack is. A selection that keeps only callstacks whose
state is known gives the model of the reference; one that keeps a
callstack whose state is unavailable answers Top. After an interruption,
a selection that no callstack reaches answers Top and is not empty, unless
it names its callstacks and the records classify each callstack it keeps:
the analysis could have reached the point on a callstack that it did not
enter. A selection that names its callstacks and keeps none of them is
empty: no callstack, Bottom, and is_empty true, whatever the state of the
callstacks that its predicate rejects. The state of a callstack that
reaches the point is the one that the analysis computed, as on one
callstack.

In interrupted.i, the reference and the candidate enumerate the same
callstacks with the same subrequests; only models and is_empty differ.
At R, the state on main/f@18 is known and the state on main/f@19 is
unavailable; no callstack reaches L. The selections that name their
callstacks and keep none of them give the answers of the reference:
rejected:main/f@18 rejects a known state, rejected:main/f@19 an
unavailable one, selector-all-filter-none and selector-without-filter-only:
both kinds, and selector-none names none.
  $ selections interrupted-reference.log > interrupted-reference.sel
  $ selections interrupted.log > interrupted.sel
  $ diff interrupted-reference.sel interrupted.sel > interrupted-sel.diff
  [1]
  $ grep -c -e "^[<>] [^ ]*\.\(stacks\|by_callstack\) " interrupted-sel.diff
  0
  [1]
  $ grep -e "\.\(rejected:[^ .]*\|selector-all-filter-none\|selector-without-filter-only:[^ .]*\|selector-none\)\." interrupted-sel.diff
  [1]
  $ grep -e "^select\.R\." interrupted.sel
  select.R.unfiltered.stacks main/f@18
  select.R.unfiltered.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.unfiltered.model NO INFORMATION
  select.R.unfiltered.empty false
  select.R.selector-all.stacks main/f@18
  select.R.selector-all.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.selector-all.model error top
  select.R.selector-all.empty false
  select.R.filter-all.stacks main/f@18
  select.R.filter-all.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.filter-all.model error top
  select.R.filter-all.empty false
  select.R.only:main/f@18.stacks main/f@18
  select.R.only:main/f@18.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.only:main/f@18.model g ∈ {0}; x ∈ {1}
  select.R.only:main/f@18.empty false
  select.R.only:main/f@19.stacks
  select.R.only:main/f@19.by_callstack
  select.R.only:main/f@19.model error top
  select.R.only:main/f@19.empty false
  select.R.selector-without:main/f@18.stacks
  select.R.selector-without:main/f@18.by_callstack
  select.R.selector-without:main/f@18.model error top
  select.R.selector-without:main/f@18.empty false
  select.R.filter-without:main/f@18.stacks
  select.R.filter-without:main/f@18.by_callstack
  select.R.filter-without:main/f@18.model error top
  select.R.filter-without:main/f@18.empty false
  select.R.selector-without:main/f@19.stacks main/f@18
  select.R.selector-without:main/f@19.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.selector-without:main/f@19.model g ∈ {0}; x ∈ {1}
  select.R.selector-without:main/f@19.empty false
  select.R.filter-without:main/f@19.stacks main/f@18
  select.R.filter-without:main/f@19.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.filter-without:main/f@19.model g ∈ {0}; x ∈ {1}
  select.R.filter-without:main/f@19.empty false
  select.R.rejected:main/f@18.stacks
  select.R.rejected:main/f@18.by_callstack
  select.R.rejected:main/f@18.model error bottom
  select.R.rejected:main/f@18.empty true
  select.R.rejected:main/f@19.stacks
  select.R.rejected:main/f@19.by_callstack
  select.R.rejected:main/f@19.model error bottom
  select.R.rejected:main/f@19.empty true
  select.R.selector-all-filter-without:main/f@18.stacks
  select.R.selector-all-filter-without:main/f@18.by_callstack
  select.R.selector-all-filter-without:main/f@18.model error top
  select.R.selector-all-filter-without:main/f@18.empty false
  select.R.selector-all-filter-without:main/f@19.stacks main/f@18
  select.R.selector-all-filter-without:main/f@19.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.selector-all-filter-without:main/f@19.model g ∈ {0}; x ∈ {1}
  select.R.selector-all-filter-without:main/f@19.empty false
  select.R.selector-all-filter-none.stacks
  select.R.selector-all-filter-none.by_callstack
  select.R.selector-all-filter-none.model error bottom
  select.R.selector-all-filter-none.empty true
  select.R.selector-without-filter-only:main/f@18.stacks
  select.R.selector-without-filter-only:main/f@18.by_callstack
  select.R.selector-without-filter-only:main/f@18.model error bottom
  select.R.selector-without-filter-only:main/f@18.empty true
  select.R.selector-without-filter-only:main/f@19.stacks
  select.R.selector-without-filter-only:main/f@19.by_callstack
  select.R.selector-without-filter-only:main/f@19.model error bottom
  select.R.selector-without-filter-only:main/f@19.empty true
  select.R.selector-none.stacks
  select.R.selector-none.by_callstack
  select.R.selector-none.model error bottom
  select.R.selector-none.empty true
  select.R.filter-none.stacks
  select.R.filter-none.by_callstack
  select.R.filter-none.model error top
  select.R.filter-none.empty false
  $ grep -e "^select\.L\.\(unfiltered\|selector-all\)\." interrupted.sel
  select.L.unfiltered.stacks
  select.L.unfiltered.by_callstack
  select.L.unfiltered.model NO INFORMATION
  select.L.unfiltered.empty false
  select.L.selector-all.stacks
  select.L.selector-all.by_callstack
  select.L.selector-all.model error top
  select.L.selector-all.empty false
  $ selected interrupted.log
  0
  $ grep -e "native select\." interrupted-native.txt
  [acceptance] native select.R.unfiltered.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-all.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-all.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.only:main/f@19.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.only:main/f@19.empty equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-without:main/f@18.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-without:main/f@18.empty equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-without:main/f@18.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-without:main/f@18.empty equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-all-filter-without:main/f@18.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-all-filter-without:main/f@18.empty equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-none.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-none.empty equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.unfiltered.model equal=false reference-reads=4 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.unfiltered.empty equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.selector-all.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.selector-all.empty equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.filter-all.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.filter-all.empty equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.only:main.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.only:main.empty equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.filter-none.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.L.filter-none.empty equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  $ grep -e "native compared" interrupted-native.log
  [acceptance] native compared=112 differing=29

interrupted-three.i calls f three times: the first two calls reach R with
x = 1 and x = 3, and the third one stops before R. The known-only
selections give the models of the reference: main/f@18 alone, every
callstack but main/f@20 by a selector or by a predicate, and every
callstack by a selector with a predicate that drops main/f@20. A selector
of several callstacks with a predicate that rejects each of them is
empty, as in the reference: selector-without-filter-only:main/f@18 names
main/f@19, known, and main/f@20, unavailable, and keeps neither.
  $ run reach-reference three-reference.log interrupted-three.i
  $ run reach-candidate three.log interrupted-three.i
  $ answers three-reference.log > three-reference.txt
  $ answers three.log > three.txt
  $ diff three-reference.txt three.txt > three.diff
  [1]
  $ grep -e "stacks" three.diff
  [1]
  $ grep -e "internal R\." three.log
  [acceptance] internal R.main/f@18 before=reached after=reached
  [acceptance] internal R.main/f@19 before=reached after=reached
  [acceptance] internal R.main/f@20 before=unavailable (interrupted) after=unavailable (interrupted)
  $ selections three.log > three.sel
  $ grep -e "^select\.R\.\(unfiltered\|filter-all\|only:\|selector-without:main/f@20\|filter-without:main/f@20\|selector-all-filter-without:main/f@20\|filter-none\)" three.sel
  select.R.unfiltered.stacks main/f@18 main/f@19
  select.R.unfiltered.by_callstack main/f@19: g ∈ {1}; x ∈ {3} | main/f@18: g ∈ {0}; x ∈ {1}
  select.R.unfiltered.model NO INFORMATION
  select.R.unfiltered.empty false
  select.R.filter-all.stacks main/f@18 main/f@19
  select.R.filter-all.by_callstack main/f@19: g ∈ {1}; x ∈ {3} | main/f@18: g ∈ {0}; x ∈ {1}
  select.R.filter-all.model error top
  select.R.filter-all.empty false
  select.R.only:main/f@18.stacks main/f@18
  select.R.only:main/f@18.by_callstack main/f@18: g ∈ {0}; x ∈ {1}
  select.R.only:main/f@18.model g ∈ {0}; x ∈ {1}
  select.R.only:main/f@18.empty false
  select.R.only:main/f@19.stacks main/f@19
  select.R.only:main/f@19.by_callstack main/f@19: g ∈ {1}; x ∈ {3}
  select.R.only:main/f@19.model g ∈ {1}; x ∈ {3}
  select.R.only:main/f@19.empty false
  select.R.only:main/f@20.stacks
  select.R.only:main/f@20.by_callstack
  select.R.only:main/f@20.model error top
  select.R.only:main/f@20.empty false
  select.R.selector-without:main/f@20.stacks main/f@18 main/f@19
  select.R.selector-without:main/f@20.by_callstack main/f@19: g ∈ {1}; x ∈ {3} | main/f@18: g ∈ {0}; x ∈ {1}
  select.R.selector-without:main/f@20.model g ∈ {0; 1}; x ∈ {1; 3}
  select.R.selector-without:main/f@20.empty false
  select.R.filter-without:main/f@20.stacks main/f@18 main/f@19
  select.R.filter-without:main/f@20.by_callstack main/f@19: g ∈ {1}; x ∈ {3} | main/f@18: g ∈ {0}; x ∈ {1}
  select.R.filter-without:main/f@20.model g ∈ {0; 1}; x ∈ {1; 3}
  select.R.filter-without:main/f@20.empty false
  select.R.selector-all-filter-without:main/f@20.stacks main/f@18 main/f@19
  select.R.selector-all-filter-without:main/f@20.by_callstack main/f@19: g ∈ {1}; x ∈ {3} | main/f@18: g ∈ {0}; x ∈ {1}
  select.R.selector-all-filter-without:main/f@20.model g ∈ {0; 1}; x ∈ {1; 3}
  select.R.selector-all-filter-without:main/f@20.empty false
  select.R.filter-none.stacks
  select.R.filter-none.by_callstack
  select.R.filter-none.model error top
  select.R.filter-none.empty false
  $ grep -e "^select\.R\.\(selector-all-filter-none\|selector-without-filter-only:main/f@18\)\." three.sel
  select.R.selector-all-filter-none.stacks
  select.R.selector-all-filter-none.by_callstack
  select.R.selector-all-filter-none.model error bottom
  select.R.selector-all-filter-none.empty true
  select.R.selector-without-filter-only:main/f@18.stacks
  select.R.selector-without-filter-only:main/f@18.by_callstack
  select.R.selector-without-filter-only:main/f@18.model error bottom
  select.R.selector-without-filter-only:main/f@18.empty true
  $ selections three-reference.log > three-reference.sel
  $ diff three-reference.sel three.sel | grep -e "\.\(rejected:[^ .]*\|selector-all-filter-none\|selector-without-filter-only:[^ .]*\|selector-none\)\."
  [1]
  $ selected three.log
  0
  $ run reach-native three-native.log interrupted-three.i
  $ grep -e "native select\.R\." three-native.log > three-native.txt
  $ grep -e "equal=false" three-native.txt
  [acceptance] native select.R.unfiltered.model equal=false reference-reads=3 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-all.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-all.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.only:main/f@20.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.only:main/f@20.empty equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-without:main/f@18.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-without:main/f@18.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-without:main/f@19.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-without:main/f@19.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-all-filter-without:main/f@18.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.selector-all-filter-without:main/f@19.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-none.model equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  [acceptance] native select.R.filter-none.empty equal=false reference-reads=5 reference-resolved=0 legacy-reads=0 resolved=1
  $ grep -c -e "equal=true" three-native.txt
  83

interrupted-loop.i calls f twice from one site, on one callstack: the
first visit reaches R, and the second one stops before it. The callstack
is enumerated, by every selection that keeps it, also in a selector that
names it alone; its state, and each model that includes it, is Top. A
selector whose predicate rejects it is empty.
  $ run reach-reference loop-reference.log interrupted-loop.i
  $ run reach-candidate loop.log interrupted-loop.i
  $ grep -e "internal R\." loop.log
  [acceptance] internal R.main/f@19 before=unavailable (interrupted) after=unavailable (interrupted)
  $ selections loop-reference.log > loop-reference.sel
  $ selections loop.log > loop.sel
  $ diff loop-reference.sel loop.sel > loop-sel.diff
  [1]
  $ grep -c -e "^[<>] [^ ]*\.stacks " loop-sel.diff
  0
  [1]
  $ grep -e "^select\.R\." loop.sel
  select.R.unfiltered.stacks main/f@19
  select.R.unfiltered.by_callstack main/f@19: error top
  select.R.unfiltered.model NO INFORMATION
  select.R.unfiltered.empty false
  select.R.selector-all.stacks main/f@19
  select.R.selector-all.by_callstack main/f@19: error top
  select.R.selector-all.model error top
  select.R.selector-all.empty false
  select.R.filter-all.stacks main/f@19
  select.R.filter-all.by_callstack main/f@19: error top
  select.R.filter-all.model error top
  select.R.filter-all.empty false
  select.R.only:main/f@19.stacks main/f@19
  select.R.only:main/f@19.by_callstack main/f@19: error top
  select.R.only:main/f@19.model error top
  select.R.only:main/f@19.empty false
  select.R.rejected:main/f@19.stacks
  select.R.rejected:main/f@19.by_callstack
  select.R.rejected:main/f@19.model error bottom
  select.R.rejected:main/f@19.empty true
  select.R.selector-none.stacks
  select.R.selector-none.by_callstack
  select.R.selector-none.model error bottom
  select.R.selector-none.empty true
  select.R.filter-none.stacks
  select.R.filter-none.by_callstack
  select.R.filter-none.model error top
  select.R.filter-none.empty false
  $ selected loop.log
  0

interrupted-spec.i interprets by_spec by its specification and floor by
its builtin, then stops in f. On their callstacks, the requests at S and B
answer Bottom, as in a complete analysis. Without a callstack, or with a
predicate, a request answers Top and is_empty false: the rest of the
analysis could have called by_spec or floor on another callstack. A
selector that names the callstack answers Bottom and is empty, as does a
selector whose predicate rejects the callstack, or that names none.
  $ run reach-reference spec-reference.log interrupted-spec.i -eva-use-spec by_spec
  $ run reach-candidate spec.log interrupted-spec.i -eva-use-spec by_spec
  $ grep -e "internal" -e "stop requested" spec.log
  [acceptance] stop requested at main/f@29/stop_analysis@23
  [acceptance] internal S.main/by_spec@27 before=body not analyzed after=body not analyzed
  [acceptance] internal B.main/floor@28 before=body not analyzed after=body not analyzed
  $ answers spec-reference.log > spec-reference.txt
  $ answers spec.log > spec.txt
  $ diff spec-reference.txt spec.txt
  18,21c18,21
  < reach.S.reachable false
  < reach.S.empty-before true
  < reach.S.empty-after true
  < reach.S.model-before error bottom
  ---
  > reach.S.reachable true
  > reach.S.empty-before false
  > reach.S.empty-after false
  > reach.S.model-before NO INFORMATION
  29,32c29,32
  < reach.B.reachable false
  < reach.B.empty-before true
  < reach.B.empty-after true
  < reach.B.model-before error bottom
  ---
  > reach.B.reachable true
  > reach.B.empty-before false
  > reach.B.empty-after false
  > reach.B.model-before NO INFORMATION
  [1]
  $ served spec.log
  0
  $ selections spec.log > spec.sel
  $ grep -e "^select\.S\.[^ ]*\.\(model\|empty\) " spec.sel
  select.S.unfiltered.model NO INFORMATION
  select.S.unfiltered.empty false
  select.S.selector-all.model error bottom
  select.S.selector-all.empty true
  select.S.filter-all.model error top
  select.S.filter-all.empty false
  select.S.only:main/by_spec@27.model error top
  select.S.only:main/by_spec@27.empty false
  select.S.rejected:main/by_spec@27.model error bottom
  select.S.rejected:main/by_spec@27.empty true
  select.S.selector-none.model error bottom
  select.S.selector-none.empty true
  select.S.filter-none.model error top
  select.S.filter-none.empty false
  $ selected spec.log
  0

The model of a selection is Bottom exactly when is_empty answers true, in
each candidate above; the sections below check the other candidates.
  $ for log in points.log interrupted.log three.log loop.log spec.log hit.log; do inconsistent $log | sed "s/^/$log /"; done

Results that are not recorded. With -eva-no-results-function f, the
states of f are not recorded; with -eva-no-results-domain cvalue or
-eva-no-results, no state is. The legacy is_empty answers true wherever no
state is recorded, so that P, which f reaches, and even C in main look
unreachable. The hit log tells that these results are unavailable, and
is_empty answers false: this is the only difference with the reference.
The other requests give the legacy answers: Top on one callstack, a top
model without callstack, reachable, and no callstack. The same holds under
every selection that keeps a callstack or does not name its callstacks:
only is_empty differs. A selection that names its callstacks and keeps
none of them is empty: Bottom, where the reference answers Top; both
answer is_empty true.
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
  $ selections nrf-reference.log > nrf-reference.sel
  $ selections nrf.log > nrf.sel
  $ diff nrf-reference.sel nrf.sel > nrf-sel.diff
  [1]
  $ grep -c -e "^<" nrf-sel.diff
  36
  $ grep -c -e "^< [^ ]*\.empty true$" nrf-sel.diff
  24
  $ grep -c -e "^< [^ ]*\.model error top$" nrf-sel.diff
  12
  $ grep -c -e "^> [^ ]*\.model error bottom$" nrf-sel.diff
  12
  $ selected nrf.log
  0
  $ consistent nrf.log
  0

consistent counts the selections of the reference whose model is Top
while is_empty answers true: each one that the diff above lists.
  $ consistent nrf-reference.log
  36
  $ grep -e "internal [UP]\." nrf.log
  [acceptance] internal U.main/f@38 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal U.main/f@39 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal P.main/f@38 before=unavailable (not recorded) after=unavailable (not recorded)
  [acceptance] internal P.main/f@39 before=unavailable (not recorded) after=unavailable (not recorded)
  $ grep -e "call fn\.f\.\(status\|available\)" -e "call reach\.P\.\(stacks\|reachable\|model-before\|before\.\)" nrf.log
  [acceptance] call fn.f.status legacy-reads=0 resolved=1 answer=analyzed without results
  [acceptance] call fn.f.available legacy-reads=0 resolved=1 answer=false
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
  $ selections nrd-reference.log > nrd-reference.sel
  $ selections nrd.log > nrd.sel
  $ diff nrd-reference.sel nrd.sel > nrd-sel.diff
  [1]
  $ grep -c -e "^<" nrd-sel.diff
  57
  $ grep -c -e "^< [^ ]*\.empty true$" nrd-sel.diff
  39
  $ grep -c -e "^< [^ ]*\.model error top$" nrd-sel.diff
  18
  $ grep -c -e "^> [^ ]*\.model error bottom$" nrd-sel.diff
  18
  $ selected nrd.log
  0
  $ consistent nrd.log
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
  [acceptance] call fn.f.status legacy-reads=0 resolved=1 answer=analyzed complete
  [acceptance] call fn.f.available legacy-reads=0 resolved=1 answer=true
  [acceptance] call fn.f.start.main/f@38 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call fn.f.start.main/f@39 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call reach.C.stacks legacy-reads=0 resolved=1 answer=
  [acceptance] call reach.C.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call reach.C.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call reach.C.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
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
  $ selections nr-reference.log > nr-reference.sel
  $ selections nr.log > nr.sel
  $ diff nr-reference.sel nr.sel > nr-sel.diff
  [1]
  $ diff nrd-sel.diff nr-sel.diff
  $ selected nr.log
  0
  $ consistent nr.log
  0
  $ grep -e "call fn\.f\.\(status\|available\)" nr.log
  [acceptance] call fn.f.status legacy-reads=0 resolved=1 answer=analyzed without results
  [acceptance] call fn.f.available legacy-reads=0 resolved=1 answer=false

Pending results. While the analysis runs, f calls pending_probe, and the
driver makes requests on the callstack of f. No result is available yet:
the hit log answers that they are pending. The legacy is_empty answers
true at P; the candidate answers false. The other answers are the legacy
ones: Top on the callstack and without callstack, no callstack, reachable,
Eva.Analysis.status partial and no result available. Under every
selection, no callstack is enumerated. The model is Top and is_empty
answers false, except for a selection that names its callstacks and keeps
none of them: it is empty, Bottom with is_empty true, where the reference
answers Top with is_empty true. These answers are not kept: after the
analysis, the same requests answer the state of the call and its
callstack.
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
  $ grep -e "call pending\." pending.log | grep -v -e "call pending\.select\."
  [acceptance] call pending.P.reachable legacy-reads=0 resolved=1 answer=true
  [acceptance] call pending.P.empty-before legacy-reads=0 resolved=1 answer=false
  [acceptance] call pending.P.stacks legacy-reads=0 resolved=1 answer=
  [acceptance] call pending.P.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] call pending.P.before.main/f@16 legacy-reads=0 resolved=1 answer=error top
  [acceptance] call pending.fn.f.status legacy-reads=0 resolved=1 answer=analyzed partial
  [acceptance] call pending.fn.f.available legacy-reads=0 resolved=1 answer=false
  $ selections pending-reference.log > pending-reference.sel
  $ selections pending.log > pending.sel
  $ diff pending-reference.sel pending.sel
  4c4
  < pending.select.P.unfiltered.empty true
  ---
  > pending.select.P.unfiltered.empty false
  8c8
  < pending.select.P.selector-all.empty true
  ---
  > pending.select.P.selector-all.empty false
  12c12
  < pending.select.P.filter-all.empty true
  ---
  > pending.select.P.filter-all.empty false
  16c16
  < pending.select.P.only:main/f@16.empty true
  ---
  > pending.select.P.only:main/f@16.empty false
  19c19
  < pending.select.P.rejected:main/f@16.model error top
  ---
  > pending.select.P.rejected:main/f@16.model error bottom
  23c23
  < pending.select.P.selector-none.model error top
  ---
  > pending.select.P.selector-none.model error bottom
  28c28
  < pending.select.P.filter-none.empty true
  ---
  > pending.select.P.filter-none.empty false
  [1]
  $ grep -e "pending\.select\.P\.selector-all\." pending.sel
  pending.select.P.selector-all.stacks
  pending.select.P.selector-all.by_callstack
  pending.select.P.selector-all.model error top
  pending.select.P.selector-all.empty false
  $ selected pending.log
  0
  $ consistent pending.log
  0
  $ grep -e "call reach\.P\.\(stacks\|model-before\) " pending.log
  [acceptance] call reach.P.stacks legacy-reads=0 resolved=1 answer=main/f@16
  [acceptance] call reach.P.model-before legacy-reads=0 resolved=1 answer=g ∈ {0}; x ∈ {1}

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
  $ selections recursion-reference.log > recursion-reference.sel
  $ selections recursion.log > recursion.sel
  $ diff recursion-reference.sel recursion.sel
  $ selected recursion.log
  0
  $ grep -e "internal" -e "call fn\.rec\.status" -e "call reach\.R\.\(before\|reachable-pos\)\." recursion.log
  [acceptance] call fn.rec.status legacy-reads=0 resolved=1 answer=analyzed partial
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
  $ selections top-reference.log > top-reference.sel
  $ selections top.log > top.sel
  $ diff top-reference.sel top.sel
  $ grep -e "^select\.T\.\(unfiltered\|selector-all\)\." top.sel
  select.T.unfiltered.stacks main
  select.T.unfiltered.by_callstack main: NO INFORMATION
  select.T.unfiltered.model NO INFORMATION
  select.T.unfiltered.empty false
  select.T.selector-all.stacks main
  select.T.selector-all.by_callstack main: NO INFORMATION
  select.T.selector-all.model NO INFORMATION
  select.T.selector-all.empty false
  $ selected top.log
  0
  $ grep -e "internal" -e "call reach\.T\.\(model-before\|before\.\)" -e "call supplied-top" top.log
  [acceptance] call reach.T.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] internal T.main before=reached after=reached
  [acceptance] call reach.T.before.main legacy-reads=0 resolved=1 answer=NO INFORMATION
  [acceptance] call supplied-top.model legacy-reads=0 resolved=0 answer=NO INFORMATION
  [acceptance] call supplied-top.empty legacy-reads=0 resolved=0 answer=true
  $ grep -e "call reach\.U\.model-before" nrf.log
  [acceptance] call reach.U.model-before legacy-reads=0 resolved=1 answer=NO INFORMATION

Empty selections. A selection that names its callstacks and keeps none
of them is empty: an empty selector (selector-none), and a selector with
a predicate that rejects its callstack (rejected:), each of its
callstacks (selector-all-filter-none) or each callstack it names
(selector-without-filter-only:). In every candidate above, after a
complete or an interrupted analysis, with memexec, with results not
recorded and during the analysis, each one answers no callstack, no
subrequest, Bottom and is_empty true, from the hit log without legacy
read, whatever the state of the callstacks that the predicate rejects:
known, unavailable, not analyzed or not recorded. empties counts their
distinct answers.
  $ empties () { sed -n 's/^\[acceptance\] call \(pending\.\)\{0,1\}select\.[^ ]*\.\(selector-none\|rejected:[^ .]*\|selector-all-filter-none\|selector-without-filter-only:[^ .]*\)\.\([a-z_]*\) \(legacy-reads=[^ ]* resolved=[^ ]*\) answer=\(.*\)$/\3 \4 answer=\5/p' "$@" | sort | uniq -c; }
  $ empties points.log interrupted.log hit.log three.log loop.log spec.log nrf.log nrd.log nr.log pending.log recursion.log top.log
      135 by_callstack legacy-reads=0 resolved=1 answer=
      135 empty legacy-reads=0 resolved=1 answer=true
      135 model legacy-reads=0 resolved=1 answer=error bottom
      135 stacks legacy-reads=0 resolved=1 answer=

The reference answers the same, except where its states are not recorded
or pending: it answers Top there, with is_empty true. emptydiff lists, for
each fixture, the answers of the reference that differ.
  $ selections spec-reference.log > spec-reference.sel
  $ emptydiff () { for f in "$@"; do diff $f-reference.sel $f.sel | sed -n "s/^< \(pending\.\)\{0,1\}select\.[^ ]*\.\(selector-none\|rejected:[^ .]*\|selector-all-filter-none\|selector-without-filter-only:[^ .]*\)\.\([a-z_]*\) \(.*\)$/$f \3 \4/p"; done | sort | uniq -c; }
  $ emptydiff points interrupted hit three loop spec nrf nrd nr pending recursion top
       18 nr model error top
       18 nrd model error top
       12 nrf model error top
        2 pending model error top

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
