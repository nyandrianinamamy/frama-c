Acceptance driver for Eva result queries and the legacy-read guard
(prototype, see plugins/inout/prototype-state-query).

Positive control. The trap is armed for the request phase only. The control
request reads the legacy store, which aborts the run with the reader and
the phase of the read.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:request legacy-reads.i > control.log 2>&1
  [1]
  $ grep -e "^\[acceptance\]" -e "legacy result-store" -e "aborted" control.log
  [acceptance] mode=trap:request guard=trap:request
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] control Eva.Results.(before P |> get_cvalue_model)
  [eva] User Error: legacy result-store read trapped: phase=request reader=Eva.Results.get_cvalue_model access=availability store=analysis-status point=before line 8 of f via=Eva.Results.get_cvalue_model_result
  [kernel] Plug-in eva aborted: invalid user input.

The trap can target another phase. In the analysis phase, the first read is
the engine's registration of the entry state of main, which joins the new
state with the recorded one. In the collection phase, it is Eva's own
statistics hook, and after the analysis, the marking of unreachable
properties. No read happens during initialization.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:analysis legacy-reads.i > analysis.log 2>&1
  [1]
  $ grep -e "legacy result-store" analysis.log
  [eva] User Error: legacy result-store read trapped: phase=analysis reader=Eva.Engine.register_state access=getter store=cvalue point=start of main in main
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:collection legacy-reads.i > collection.log 2>&1
  [1]
  $ grep -e "legacy result-store" collection.log
  [eva] User Error: legacy result-store read trapped: phase=collection reader=Eva.Summary.compute_fun_stats access=availability store=analysis-status point=before line 6 of f via=Eva.Results.is_reachable
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:post-analysis legacy-reads.i > post-analysis.log 2>&1
  [1]
  $ grep -e "legacy result-store" post-analysis.log
  [eva] User Error: legacy result-store read trapped: phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status point=before line 12 of main via=Eva.Results.is_reachable
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance trap:initialization legacy-reads.i > initialization.log 2>&1
  $ grep -e "^\[acceptance\] control" initialization.log
  [acceptance] control not trapped in phase initialization

Reference. A separate process runs fresh-only Eva (memexec off) with the
guard off; reads are not observed.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance reference -inout-state-query-acceptance-output reference.jsonl legacy-reads.i > reference.log 2>&1
  $ grep -e "^\[acceptance\] mode" -e "^\[acceptance\] config" -e "^\[acceptance\] call value.g" -e "^\[acceptance\] accounting" reference.log
  [acceptance] mode=reference guard=off
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] call value.g.before-P legacy-reads=unobserved answer={4; 9}
  [acceptance] call value.g.before-P.main/f@15 legacy-reads=unobserved answer={4}
  [acceptance] call value.g.before-P.main/f@18 legacy-reads=unobserved answer={9}
  [acceptance] accounting logged=0 attributed=0

Candidate. The guard records every legacy read. The driver groups the reads
of the execution by phase and reader, and attributes the other reads to the
public request that made them. Registration-time reads come from the engine
and from InOut's collection; final printing and logic initialization read
the store without Eva.Results. The request on a supplied state reads nothing.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate -inout-state-query-acceptance-output candidate.jsonl legacy-reads.i > candidate.log 2>&1
  $ grep -e "^\[acceptance\]" candidate.log
  [acceptance] mode=candidate guard=record
  [acceptance] config -eva-domains=cvalue -eva-slevel=0 -eva-memexec=false -eva-results=true -eva-join-results=true -eva-no-results-domain= -eva-no-results-function=@default
  [acceptance] execution phase=analysis reader=Eva.Engine.register_state access=getter store=cvalue
  [acceptance] execution phase=analysis reader=Eva.Eval_terms.add_init access=getter store=cvalue
  [acceptance] execution phase=collection reader=Eva.Summary.compute_fun_stats access=availability store=analysis-status
  [acceptance] execution phase=collection reader=Eva.Results.get_cvalue_model access=availability store=analysis-status
  [acceptance] execution phase=collection reader=Eva.Eval_terms.add_init access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Eval_annots.mark_unreachable access=enumeration store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Summary.compute_fun_stats access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Summary.compute_fun_stats access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Engine.consolidate access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Engine.consolidate access=enumeration store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Engine.consolidate access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Cvalue_domain.display_final_state access=getter store=cvalue
  [acceptance] execution phase=post-analysis reader=Eva.Cvalue_domain.display_final_state access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Summary.compute_statuses access=availability store=analysis-status
  [acceptance] execution phase=post-analysis reader=Eva.Summary.compute_statuses access=getter store=cvalue
  [acceptance] call stacks.before-P legacy-reads=4 answer=main/f@15 main/f@18
  [acceptance] call by_callstack.before-P legacy-reads=4 answer=main/f@15 main/f@18
  [acceptance] call available.f legacy-reads=1 answer=true
  [acceptance] call status.f legacy-reads=1 answer=analyzed complete
  [acceptance] call reachable.P legacy-reads=2 answer=true
  [acceptance] call model.before-P legacy-reads=2 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@15 legacy-reads=2 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@18 legacy-reads=2 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P legacy-reads=2 answer=g ∈ {4; 9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@15 legacy-reads=2 answer=g ∈ {4}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.after-P.main/f@18 legacy-reads=2 answer=g ∈ {9}; y ∈ {11}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call value.g.before-P legacy-reads=2 answer={4; 9}
  [acceptance] call value.g.before-P.main/f@15 legacy-reads=2 answer={4}
  [acceptance] call value.g.before-P.main/f@18 legacy-reads=2 answer={9}
  [acceptance] call value.y.before-P legacy-reads=2 answer={11}
  [acceptance] call value.y.before-P.main/f@15 legacy-reads=2 answer={11}
  [acceptance] call value.y.before-P.main/f@18 legacy-reads=2 answer={11}
  [acceptance] call model.start-of-f legacy-reads=2 answer=g ∈ {4; 9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.initial legacy-reads=2 answer=g ∈ {0}; y ∈ {0}
  [acceptance] call export.get_results legacy-reads=62 answer=exported
  [acceptance] call supplied-state.eval legacy-reads=0 answer={5}
  [acceptance] accounting logged=341 attributed=341
