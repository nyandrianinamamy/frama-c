Acceptance driver for Eva result queries and the legacy-read guard
(prototype, see plugins/inout/prototype-state-query).

Positive control. The trap is armed for the request phase only. The control
request reads the legacy store, which aborts the run with the reader and
the phase of the read.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:request legacy-reads.i > control.log 2>&1
  [1]
  $ grep -e "^\[acceptance\]" -e "legacy result-store" -e "aborted" control.log
  [acceptance] mode=trap:request guard=trap:request
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-hit-log=true -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] control Eva.Results.(before P |> get_cvalue_model)
  [eva] User Error: legacy result-store read trapped: phase=request reader=Eva.Results.get_cvalue_model access=availability store=analysis-status point=before line 8 of f via=Eva.Results.get_cvalue_model_result
  [kernel] Plug-in eva aborted: invalid user input.

The trap can target another phase. In the analysis phase, the first read is
the engine's registration of the entry state of main, which joins the new
state with the recorded one. In the collection phase, it is the Init label
of the assertion, which reads the initial state, and after the analysis,
the marking of the postconditions of unreachable returns, which reads the
analysis status of each function. Eva's statistics and its marking of
unreachable annotations ask Eva.Results.is_reachable, which the hit log
answers without read. No read happens during initialization.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:analysis legacy-reads.i > analysis.log 2>&1
  [1]
  $ grep -e "legacy result-store" analysis.log
  [eva] User Error: legacy result-store read trapped: phase=analysis reader=Eva.Engine.register_state access=getter store=cvalue point=start of main in main
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:collection legacy-reads.i > collection.log 2>&1
  [1]
  $ grep -e "legacy result-store" collection.log
  [eva] User Error: legacy result-store read trapped: phase=collection reader=Eva.Eval_terms.add_init access=getter store=cvalue point=initial state
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:post-analysis legacy-reads.i > post-analysis.log 2>&1
  [1]
  $ grep -e "legacy result-store" post-analysis.log
  [eva] User Error: legacy result-store read trapped: phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status point=f
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

Candidate. The guard records every legacy read, and every answer of the
resolver of the hit log. The driver groups the reads of the execution by
phase and reader, and attributes the other reads and the resolutions to the
public request that made them. Registration-time reads come from the
engine; InOut takes the state at the start of each call without a request,
and its remaining collection read is the Init label of the assertion. Final
printing and logic initialization read the store without Eva.Results. The
requests on a supplied stack are resolved without legacy read; the request
on a supplied state reads nothing.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate -inout-state-query-acceptance-output candidate.jsonl legacy-reads.i > candidate.log 2>&1
  $ grep -e "^\[acceptance\]" candidate.log
  [acceptance] mode=candidate guard=record
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-hit-log=true -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] execution phase=analysis reader=Eva.Engine.register_state access=getter store=cvalue
  [acceptance] execution phase=analysis reader=Eva.Eval_terms.add_init access=getter store=cvalue
  [acceptance] execution phase=collection reader=Eva.Eval_terms.add_init access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Engine.consolidate access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Engine.consolidate access=enumeration store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Engine.consolidate access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Cvalue_domain.display_final_state access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Cvalue_domain.display_final_state access=availability store=analysis-status
  [acceptance] call stacks.before-P legacy-reads=4 resolved=0 answer=main/f@15 main/f@18
  [acceptance] call by_callstack.before-P legacy-reads=4 resolved=0 answer=main/f@15 main/f@18
  [acceptance] call available.f legacy-reads=1 resolved=0 answer=true
  [acceptance] call status.f legacy-reads=1 resolved=0 answer=analyzed complete
  [acceptance] call reachable.P legacy-reads=0 resolved=1 answer=true
  [acceptance] call model.before-P legacy-reads=2 resolved=0 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P legacy-reads=2 resolved=0 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call value.g.before-P legacy-reads=2 resolved=0 answer={4; 9}
  [acceptance] call value.g.before-P.main/f@15 legacy-reads=0 resolved=1 answer={4}
  [acceptance] call value.g.before-P.main/f@18 legacy-reads=0 resolved=1 answer={9}
  [acceptance] call value.y.before-P legacy-reads=2 resolved=0 answer={11}
  [acceptance] call value.y.before-P.main/f@15 legacy-reads=0 resolved=1 answer={11}
  [acceptance] call value.y.before-P.main/f@18 legacy-reads=0 resolved=1 answer={11}
  [acceptance] call model.start-of-f legacy-reads=2 resolved=0 answer=g ∈ {4; 9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.initial legacy-reads=2 resolved=0 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.before-pos-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-pos-P.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-pos-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-pos-P.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.initial.main legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.before-pos-root legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.after-pos-root legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; __retres ∈ {20}
  [acceptance] call stacks.start-of-f legacy-reads=4 resolved=0 answer=main/f@15 main/f@18
  [acceptance] call model.start-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-f.main/f@15 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@15 body#1: 1 entries survive the preconditions; input:; g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.start-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.body-entry-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-f.main/f@18 legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@18 body#2: 1 entries survive the preconditions; input:; g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call stacks.start-of-main legacy-reads=3 resolved=0 answer=main
  [acceptance] call model.start-of-main.main legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call model.body-entry-of-main.main legacy-reads=0 resolved=1 answer=g ∈ {0}; y ∈ {0}; __retres ∈ UNINITIALIZED
  [acceptance] call model.end-of-main.main legacy-reads=0 resolved=1 answer=g ∈ {9}; y ∈ {11}; __retres ∈ {20}
  [acceptance] visits main.main body#3: 1 entries survive the preconditions; input:; g ∈ {0}; y ∈ {0}
  [acceptance] call inout.call-f@15 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call inout.call-f@18 legacy-reads=0 resolved=0 answer=Operational inputs:; x; Operational inputs on termination:; x; Sure outputs:; y; Over outputs:; y; Over outputs on termination:; y; Logic inputs:; \nothing
  [acceptance] call export.get_results legacy-reads=62 resolved=0 answer=exported
  [acceptance] call supplied-state.eval legacy-reads=0 resolved=0 answer={5}
  [acceptance] accounting logged=209 attributed=209
