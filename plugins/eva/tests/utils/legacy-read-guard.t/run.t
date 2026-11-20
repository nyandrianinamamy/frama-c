Acceptance driver for Eva result queries and the legacy-read guard
(prototype, see plugins/inout/prototype-state-query).

Positive control. The trap is armed for the request phase only. On the
legacy path (-eva-no-hit-log), the control request reads the legacy store,
which aborts the run with the reader and the phase of the read: its first
read is the computation state. With the hit log, the resolver serves this
request.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance trap:request legacy-reads.i > control.log 2>&1
  [1]
  $ grep -e "^\[acceptance\]" -e "legacy result-store" -e "aborted" control.log
  [acceptance] mode=trap:request guard=trap:request
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-hit-log=false -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] control Eva.Results.(before P |> get_cvalue_model)
  [eva] User Error: legacy result-store read trapped: phase=request reader=Eva.Results.get_cvalue_model access=availability store=analysis-status point=computation state at before line 8 of f via=Eva.Results.get_cvalue_model_result
  [kernel] Plug-in eva aborted: invalid user input.

The trap can target another phase. On the legacy path, the first read of
the analysis is the engine's registration of the entry state of main,
which joins the new state with the recorded one. With the hit log, the
registration takes the state already registered from the records, and the
analysis reads nothing. No read happens during the collection: the
hit log answers the Init label of the assertion, which reads the initial
state, and the reachability requests of Eva's statistics hook. After the
analysis, the hit log answers the marking of unreachable properties and of
postconditions: the control runs on the legacy path, where this marking
first asks whether a statement is reachable. No read happens during
initialization.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance trap:analysis legacy-reads.i > analysis.log 2>&1
  [1]
  $ grep -e "legacy result-store" analysis.log
  [eva] User Error: legacy result-store read trapped: phase=analysis reader=Eva.Engine.register_state access=getter store=cvalue point=start of main in main
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:analysis legacy-reads.i > analysis-hit-log.log 2>&1
  $ grep -e "^\[acceptance\] control" analysis-hit-log.log
  [acceptance] control not trapped in phase analysis
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:collection legacy-reads.i > collection.log 2>&1
  $ grep -e "^\[acceptance\] control" -e "legacy result-store" collection.log
  [acceptance] control not trapped in phase collection
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance trap:post-analysis legacy-reads.i > post-analysis.log 2>&1
  [1]
  $ grep -e "legacy result-store" post-analysis.log
  [eva] User Error: legacy result-store read trapped: phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status point=computation state at before line 12 of main via=Eva.Results.is_reachable
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:initialization legacy-reads.i > initialization.log 2>&1
  $ grep -e "^\[acceptance\] control" initialization.log
  [acceptance] control not trapped in phase initialization

Reference. A separate process runs fresh-only Eva (memexec off) on the
legacy path (hit log off) with the guard off; reads are not observed.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance reference -inout-state-query-acceptance-output reference.jsonl legacy-reads.i > reference.log 2>&1
  $ grep -e "^\[acceptance\] mode" -e "^\[acceptance\] config" -e "^\[acceptance\] call value.g" -e "^\[acceptance\] accounting" reference.log
  [acceptance] mode=reference guard=off
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-hit-log=false -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] call value.g.before-P legacy-reads=unobserved resolved=unobserved answer={4; 9}
  [acceptance] call value.g.before-P.main/f@15 legacy-reads=unobserved resolved=unobserved answer={4}
  [acceptance] call value.g.before-P.main/f@18 legacy-reads=unobserved resolved=unobserved answer={9}
  [acceptance] accounting logged=0 attributed=0

Candidate. The guard is armed once, before the analysis, with the trap of
every phase: any legacy read, in any phase, would abort the run. The guard
also logs every answer of the resolver of the hit log; the driver
attributes each one to the public request that made it. During the
analysis, the engine registers each state, each analysis status and
callers, and each fired branch from the records of the hit log, and only
writes the legacy tables. InOut takes the state at the start of each call
without a request, and the hit log answers the Init label of the
assertion. After the analysis, the readers through Eva.Results, the
marking of postconditions and the final printing are resolved, and the
store is not consolidated. The requests on a supplied stack, on several
stacks and on none, and the availability readers, are resolved. The
snapshot export rebuilds its states, and the callers and the analysis
status of each function, from the hit log. The request on a supplied state
reads nothing. The driver then prints, for each phase, its entries while
the guard was armed, its reads and its resolutions, those of the three
writers of the registration included, and the state of the guard: armed
once with the trap of every phase, no read logged, none trapped.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate -inout-state-query-acceptance-output candidate.jsonl legacy-reads.i > candidate.log 2>&1
  $ grep -e "^\[acceptance\]" candidate.log
  [acceptance] mode=candidate guard=trap:all
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-hit-log=true -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] call stacks.before-P legacy-reads=0 resolved=1 answer=main/f@15 main/f@18
  [acceptance] call by_callstack.before-P legacy-reads=0 resolved=1 answer=main/f@15 main/f@18
  [acceptance] call available.f legacy-reads=0 resolved=1 answer=true
  [acceptance] call status.f legacy-reads=0 resolved=1 answer=analyzed complete
  [acceptance] call reachable.P legacy-reads=0 resolved=1 answer=true
  [acceptance] call reachable-kinstr.P legacy-reads=0 resolved=1 answer=true
  [acceptance] call reachable-pos.P.main/f@15 legacy-reads=0 resolved=1 answer=true
  [acceptance] call reachable-pos.P.main/f@18 legacy-reads=0 resolved=1 answer=true
  [acceptance] call model.before-P legacy-reads=0 resolved=1 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P legacy-reads=0 resolved=1 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call value.g.before-P legacy-reads=0 resolved=1 answer={4; 9}
  [acceptance] call value.g.before-P.main/f@15 legacy-reads=0 resolved=1 answer={4}
  [acceptance] call value.g.before-P.main/f@18 legacy-reads=0 resolved=1 answer={9}
  [acceptance] call value.y.before-P legacy-reads=0 resolved=1 answer={11}
  [acceptance] call value.y.before-P.main/f@15 legacy-reads=0 resolved=1 answer={11}
  [acceptance] call value.y.before-P.main/f@18 legacy-reads=0 resolved=1 answer={11}
  [acceptance] call model.start-of-f legacy-reads=0 resolved=1 answer=g ∈ {4; 9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.initial legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.before-pos-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-pos-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-pos-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-pos-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.initial.main legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.before-pos-root legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.after-pos-root legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; __retres ∈ {20}
  [acceptance] call stacks.start-of-f legacy-reads=0 resolved=1 answer=main/f@15 main/f@18
  [acceptance] call model.start-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@15 body#1: 1 entries survive the preconditions; input:; g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.start-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@18 body#2: 1 entries survive the preconditions; input:; g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call stacks.start-of-main legacy-reads=0 resolved=1 answer=main
  [acceptance] call model.start-of-main.main legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.body-entry-of-main.main legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-main.main legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; __retres ∈ {20}
  [acceptance] visits main.main body#3: 1 entries survive the preconditions; input:; g ∈ {0}; y ∈ {0}
  [acceptance] call inout.call-f@15 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call inout.call-f@18 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call export.get_results legacy-reads=0 resolved=28 answer=exported
  [acceptance] call export.calls legacy-reads=0 resolved=28 answer=main: analyzed complete; callers: none; f: analyzed complete; callers: main@15,18
  [acceptance] call supplied-state.eval legacy-reads=0 resolved=0 answer={5}
  [acceptance] accounting logged=0 attributed=0
  [acceptance] scope initialization entries=2 reads=0 resolutions=0 registrations=Eva.Engine.register_state:0,Eva.Function_calls.register_analysis_target:0,Eva.Iterator.record_fireable:0
  [acceptance] scope analysis entries=1 reads=0 resolutions=37 registrations=Eva.Engine.register_state:33,Eva.Function_calls.register_analysis_target:3,Eva.Iterator.record_fireable:0
  [acceptance] scope collection entries=24 reads=0 resolutions=16 registrations=Eva.Engine.register_state:0,Eva.Function_calls.register_analysis_target:0,Eva.Iterator.record_fireable:0
  [acceptance] scope post-analysis entries=1 reads=0 resolutions=62 registrations=Eva.Engine.register_state:0,Eva.Function_calls.register_analysis_target:0,Eva.Iterator.record_fireable:0
  [acceptance] scope request entries=45 reads=0 resolutions=96 registrations=Eva.Engine.register_state:0,Eva.Function_calls.register_analysis_target:0,Eva.Iterator.record_fireable:0
  [acceptance] gate arms=trap:all final=trap:all logged=0 trapped=0 passes=true

The same command on the legacy path aborts at the first read of the
analysis.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -eva-no-hit-log -inout-state-query-acceptance candidate legacy-reads.i > continuous-legacy.log 2>&1
  [1]
  $ grep -e "legacy result-store" continuous-legacy.log
  [eva] User Error: legacy result-store read trapped: phase=analysis reader=Eva.Engine.register_state access=getter store=cvalue point=start of main in main

Tail probe: after the battery, still under the trap and with no read
logged, the results are cleared and one request is made. The hit log no
longer describes the results, so the request reads the legacy store, and
the trap, still armed, aborts the run.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance tail-probe legacy-reads.i > tail-probe.log 2>&1
  [1]
  $ grep -e "^\[acceptance\] \(gate\|tail-probe\)" -e "legacy result-store" tail-probe.log
  [acceptance] gate arms=trap:all final=trap:all logged=0 trapped=0 passes=true
  [acceptance] tail-probe logged=0 trapped=0
  [acceptance] tail-probe Eva.Results.(before <first statement of main> |> get_cvalue_model) on cleared results
  [eva] User Error: legacy result-store read trapped: phase=request reader=Eva.Results.get_cvalue_model access=availability store=analysis-status point=computation state at before line 12 of main via=Eva.Results.get_cvalue_model_result
