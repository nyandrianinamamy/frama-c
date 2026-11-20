Final values, the logic label Init and snapshots of the results of Eva,
read from the hit log (prototype, see plugins/inout/prototype-state-query).

The script reconstructed.ml supplies the initial memory and the argument n
of main, and analyzes inputs.i twice: with g = 7 and n = 10, then with
g = 3 and n = 20. It saves the results of each analysis, clears them, and
restores each snapshot in turn. After each analysis and each restoration,
it replays the same requests and writes their answers to a file: fresh-1,
fresh-2, restored-1 and restored-2. See the script for the requests.
  $ dune build --cache=disabled --root . _build/default/reconstructed.cmxs

Candidate. The guard records every legacy read. FORBID makes the first
legacy read of a migrated reader abort the run: the final printing
(display), the label Init (init), the export of a snapshot, with its
states and the callers and analysis status of each function, and its
restoration (export), and every read of the requests replayed on restored
results (replay). The run completes. The checks, which read the label
Init, are valid with the supplied g = 7 and invalid with g = 3, and keep
their status once restored. The script lists the reads of the migrated
readers and of the snapshot functions only: none remains. The hit log
served each migrated reader.
  $ mkdir candidate reference
  $ FORBID=display,init,export,replay ANSWERS=candidate frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec inputs.i > candidate.log 2>&1
  $ grep -e "^\[reconstructed\]" -e "legacy result-store" candidate.log
  [reconstructed] analysis 1: g = 7 in the supplied memory, n = 10
  [reconstructed] status f_init: VALID
  [reconstructed] status main_init: VALID
  [reconstructed] fresh-1: replayed with no legacy read
  [reconstructed] snapshot 1: exported with no legacy read
  [reconstructed] analysis 2: g = 3 in the supplied memory, n = 20
  [reconstructed] status f_init: **NOT** VALID
  [reconstructed] status main_init: **NOT** VALID
  [reconstructed] fresh-2: replayed with no legacy read
  [reconstructed] snapshot 2: exported with no legacy read
  [reconstructed] snapshot 1: restored with no legacy read
  [reconstructed] status f_init: VALID
  [reconstructed] status main_init: VALID
  [reconstructed] restored-1: replayed with no legacy read
  [reconstructed] snapshot 2: restored with no legacy read
  [reconstructed] status f_init: **NOT** VALID
  [reconstructed] status main_init: **NOT** VALID
  [reconstructed] restored-2: replayed with no legacy read
  [reconstructed] display: no legacy read, answers of the hit log
  [reconstructed] init: no legacy read, answers of the hit log
  [reconstructed] export: no legacy read, answers of the hit log

Reference. A separate process runs the same script on the legacy path,
fresh-only: every migrated reader reads the legacy store, and the hit log
serves none.
  $ ANSWERS=reference frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-hit-log inputs.i > reference.log 2>&1
  $ grep -e "replayed" -e "exported" -e "restored with" -e "hit log" -e "legacy result-store" reference.log
  [reconstructed] fresh-1: replayed with legacy reads
  [reconstructed] snapshot 1: exported with legacy reads
  [reconstructed] fresh-2: replayed with legacy reads
  [reconstructed] snapshot 2: exported with legacy reads
  [reconstructed] snapshot 1: restored with no legacy read
  [reconstructed] restored-1: replayed with legacy reads
  [reconstructed] snapshot 2: restored with no legacy read
  [reconstructed] restored-2: replayed with legacy reads
  [reconstructed] display: legacy reads, no answer of the hit log
  [reconstructed] init: legacy reads, no answer of the hit log
  [reconstructed] export: legacy reads, no answer of the hit log

The output of Eva is the same in both processes: the initial state, the
final values, the alarms, the statuses and the summary of each analysis.
  $ grep -v -e "^\[reconstructed\]" reference.log > reference-eva.txt
  $ grep -v -e "^\[reconstructed\]" candidate.log > candidate-eva.txt
  $ diff reference-eva.txt candidate-eva.txt
  $ grep -A2 -e "Values at end of function" candidate.log
  [eva:final-states] Values at end of function f:
    y ∈ {14; 19}
  [eva:final-states] Values at end of function main:
    g ∈ {9}
    y ∈ {19}
  --
  [eva:final-states] Values at end of function f:
    y ∈ {24; 29}
  [eva:final-states] Values at end of function main:
    g ∈ {9}
    y ∈ {29}

The answers of the replayed requests are the same in both processes, after
each analysis and after each restoration. In the candidate, each restored
snapshot answers as its analysis did, although the second analysis ran
after the first was saved.
  $ diff -r reference candidate
  $ diff candidate/fresh-1 candidate/restored-1
  $ diff candidate/fresh-2 candidate/restored-2
  $ cat candidate/restored-1
  callstacks before P:
    main/f@22 main/f@24
  callstacks at the start of f:
    main/f@22 main/f@24
  before P:
    g ∈ {4; 9}
    y ∈ {14; 19}
    x ∈ {10}
    n ∈ {10}
  after P:
    g ∈ {4; 9}
    y ∈ {14; 19}
    x ∈ {10}
    n ∈ {10}
  before P on main/f@22:
    g ∈ {4}
    y ∈ {14}
    x ∈ {10}
    n ∈ {10}
  after P on main/f@22:
    g ∈ {4}
    y ∈ {14}
    x ∈ {10}
    n ∈ {10}
  before P on main/f@24:
    g ∈ {9}
    y ∈ {19}
    x ∈ {10}
    n ∈ {10}
  after P on main/f@24:
    g ∈ {9}
    y ∈ {19}
    x ∈ {10}
    n ∈ {10}
  g before P on the selected callstacks:
    {4; 9}
  g before P on the callstack that the predicate keeps:
    {9}
  g before P on no callstack:
    error bottom
  initial state:
    g ∈ {7}
    y ∈ {0}
  start of main:
    g ∈ {7}
    y ∈ {0}
    n ∈ {10}
  P reachable:
    true
  before P empty:
    false
  D reachable:
    false
  before D empty:
    true
  before D:
    error bottom
  f available: true
  f status: analyzed complete
  main status: analyzed complete

Unavailable results. Without saved results for f, the states at P are
unavailable: Top, not Bottom, on each callstack and joined, and P is
reachable. A restored snapshot keeps these answers, and the dead statement
D stays unreachable.
  $ mkdir no-results no-results-reference
  $ FORBID=display,init,export,replay ANSWERS=no-results frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-results-function f inputs.i > no-results.log 2>&1
  $ grep -e "replayed" -e "legacy result-store" no-results.log
  [reconstructed] fresh-1: replayed with no legacy read
  [reconstructed] fresh-2: replayed with no legacy read
  [reconstructed] restored-1: replayed with no legacy read
  [reconstructed] restored-2: replayed with no legacy read
  $ diff no-results/fresh-1 no-results/restored-1
  $ diff no-results/fresh-2 no-results/restored-2
  $ cat no-results/restored-1
  callstacks before P:
    none
  callstacks at the start of f:
    main/f@22 main/f@24
  before P:
    NO INFORMATION
  after P:
    NO INFORMATION
  before P on main/f@22:
    error top
  after P on main/f@22:
    error top
  before P on main/f@24:
    error top
  after P on main/f@24:
    error top
  g before P on the selected callstacks:
    error top
  g before P on the callstack that the predicate keeps:
    error top
  g before P on no callstack:
    error bottom
  initial state:
    g ∈ {7}
    y ∈ {0}
  start of main:
    g ∈ {7}
    y ∈ {0}
    n ∈ {10}
  P reachable:
    true
  before P empty:
    false
  D reachable:
    false
  before D empty:
    true
  before D:
    error bottom
  f available: false
  f status: analyzed without results
  main status: analyzed complete

The reference differs on two answers, the same after each analysis and
each restoration, where the hit log answers by design otherwise than the
legacy store (see stack-selection.t and reach-availability.t). A selection
of no callstack is empty, Bottom, whereas the legacy store answers Top
when f has no saved results. A request whose state is unavailable is not
empty, whereas the legacy store finds no callstack at P.
  $ ANSWERS=no-results-reference frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-results-function f -eva-no-hit-log inputs.i > no-results-reference.log 2>&1
  $ diff no-results-reference/restored-1 no-results/restored-1
  22c22
  <   error top
  ---
  >   error bottom
  33c33
  <   true
  ---
  >   false
  [1]
  $ diff no-results-reference/fresh-1 no-results-reference/restored-1

Positive controls. On the legacy path, the same traps abort the run on the
first read of each migrated reader: the label Init during the analysis,
the final printing after it, the export of the first snapshot, whose
first read is that of its states, and the first request replayed on the
restored results.
  $ FORBID=init frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-hit-log inputs.i > control-init.log 2>&1
  [1]
  $ grep -e "legacy result-store" control-init.log
  [eva] User Error: legacy result-store read trapped: phase=analysis reader=Eva.Eval_terms.add_init access=getter store=cvalue point=initial state
  $ FORBID=display frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-hit-log inputs.i > control-display.log 2>&1
  [1]
  $ grep -e "legacy result-store" control-display.log
  [eva] User Error: legacy result-store read trapped: phase=post-analysis reader=Eva.Cvalue_domain.display_final_state access=availability store=analysis-status point=before line 12 of f
  $ FORBID=export frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-hit-log inputs.i > control-export.log 2>&1
  [1]
  $ grep -e "legacy result-store" control-export.log
  [eva] User Error: legacy result-store read trapped: phase=request reader=Eva.Eva_results.get_results access=enumeration store=cvalue point=start of f via=Eva.Eva_results.export_states
  $ FORBID=replay frama-c -no-autoload-plugins -load-module eva,inout,reconstructed.cmxs -eva-domains cvalue -eva-no-memexec -eva-no-hit-log inputs.i > control-replay.log 2>&1
  [1]
  $ grep -e "replayed" -e "legacy result-store" control-replay.log
  [reconstructed] fresh-1: replayed with legacy reads
  [reconstructed] fresh-2: replayed with legacy reads
  [eva] User Error: legacy result-store read trapped: phase=request reader=Eva.Results.callstacks access=availability store=analysis-status point=before line 12 of f

Final values without the script, on hit.i. With memexec, the second call
to f is a hit: the hit log declines the states of f, and the printing reads
the legacy store, which consolidates them on demand. h is recursive and
partially analyzed. The final values are the same as on the legacy path,
with and without -eva-join-results, with and without memexec, and with
the equality domain, for which the hit log records nothing.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva -eva-msg-key progress hit.i > hit.log 2>&1
  $ grep -e "Reusing" hit.log
  [eva:progress] hit.i:24: Reusing old results for call to f
  $ grep -A3 -e "Values at end of function" hit.log
  [eva:final-states] Values at end of function f:
    y ∈ {11}
  [eva:final-states] Values at end of function h:
    z ∈ [--..--]
    __retres ∈ [-2147483647..2147483647]
  [eva:final-states] Values at end of function main:
    g ∈ {9}
    y ∈ {11}
    z ∈ [--..--]
  $ for options in "" "-eva-no-join-results" "-eva-no-memexec" "-eva-no-memexec -eva-no-join-results" "-eva-domains=cvalue,equality" "-eva-domains=cvalue,equality -eva-no-join-results"; do
  >   frama-c -no-autoload-plugins -load-module eva,inout -eva $options hit.i > hit-candidate.log 2>&1 || echo "candidate failed"
  >   frama-c -no-autoload-plugins -load-module eva,inout -eva $options -eva-no-hit-log hit.i > hit-legacy.log 2>&1 || echo "legacy failed"
  >   grep -e "final-states" -e "^  " hit-candidate.log > hit-candidate.txt
  >   grep -e "final-states" -e "^  " hit-legacy.log > hit-legacy.txt
  >   echo "options [$options]: $(grep -c "Values at end" hit-candidate.txt) functions printed"
  >   diff hit-legacy.txt hit-candidate.txt
  > done
  options []: 3 functions printed
  options [-eva-no-join-results]: 3 functions printed
  options [-eva-no-memexec]: 3 functions printed
  options [-eva-no-memexec -eva-no-join-results]: 3 functions printed
  options [-eva-domains=cvalue,equality]: 3 functions printed
  options [-eva-domains=cvalue,equality -eva-no-join-results]: 3 functions printed
