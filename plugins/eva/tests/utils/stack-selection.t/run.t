Stack selection and evaluation order of requests rebuilt from the hit log
(prototype, see plugins/inout/prototype-state-query).

g is called from four sites. The loop calls it twice from line 43, on one
stack; the call at line 44 returns before P. On each stack that reaches P,
u == w holds; x == y holds on each visit, but the two visits of the loop
stack set x = y = 3, then 4.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance candidate selection.i > candidate.log 2>&1
  $ grep -e "visits g.main/g@43" candidate.log > visits.txt
  $ grep -o -e "body#[0-9]*" visits.txt
  body#6
  body#8

Enumeration. Every enumeration is served by the resolver, without legacy
read. The stacks come in the order of the legacy store, which is not the
order of the calls; the loop stack appears once. Nested stacks are
enumerated below each stack of g. The stack of line 44 reaches the start
and the end of g, but not P. by_callstack returns one subrequest per stack,
and each subrequest is served by the resolver.
  $ grep -e "call stacks.unfiltered" -e "call order.start-of-g" -e "call order.end-of-g" -e "call order.start-of-f1" -e "call stacks.unreached-P" -e "call by_callstack.unfiltered" candidate.log
  [acceptance] call stacks.unreached-P legacy-reads=0 resolved=1 answer=main/g@44
  [acceptance] call stacks.unfiltered legacy-reads=0 resolved=1 answer=main/g@43 main/g@39 main/g@40
  [acceptance] call by_callstack.unfiltered legacy-reads=0 resolved=4 answer=main/g@40: {1} main/g@39: {1} main/g@43: {0; 1}
  [acceptance] call order.start-of-f1 legacy-reads=0 resolved=1 answer=main/g@43/f1@26 main/g@39/f1@26 main/g@40/f1@26
  [acceptance] call order.start-of-g legacy-reads=0 resolved=1 answer=main/g@43 main/g@39 main/g@44 main/g@40
  [acceptance] call order.end-of-g legacy-reads=0 resolved=1 answer=main/g@43 main/g@39 main/g@44 main/g@40

Evaluation order. An unfiltered request evaluates the expression in the
joined state, where neither equality holds. A request on several stacks
evaluates it on each stack, then joins the answers, even when the
selection names every stack. The two visits of the loop stack are joined
before the evaluation: x == y gives {0; 1} on that stack alone.
  $ grep -e "call eval_exp\[x==y\]" -e "call eval_exp\[u==w\]" candidate.log | grep -v supplied
  [acceptance] call eval_exp[x==y].unfiltered legacy-reads=0 resolved=1 answer={0; 1}; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].unfiltered legacy-reads=0 resolved=1 answer={0; 1}; alarms: none; singleton: false
  [acceptance] call eval_exp[x==y].stack:main/g@39 legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[u==w].stack:main/g@39 legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].stack:main/g@40 legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[u==w].stack:main/g@40 legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].stack:main/g@43 legacy-reads=0 resolved=1 answer={0; 1}; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].stack:main/g@43 legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].selector-all legacy-reads=0 resolved=1 answer={0; 1}; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].selector-all legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].filter-all legacy-reads=0 resolved=1 answer={0; 1}; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].filter-all legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].selector-two legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[u==w].selector-two legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].filter-drop-first legacy-reads=0 resolved=1 answer={0; 1}; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].filter-drop-first legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].selector-unreached legacy-reads=0 resolved=1 answer=error bottom; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].selector-unreached legacy-reads=0 resolved=1 answer=error bottom; alarms: none; singleton: false
  [acceptance] call eval_exp[x==y].stack-rejected legacy-reads=0 resolved=1 answer=error bottom; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].stack-rejected legacy-reads=0 resolved=1 answer=error bottom; alarms: none; singleton: false
  [acceptance] call eval_exp[x==y].filter-none legacy-reads=0 resolved=1 answer=error bottom; alarms: none; singleton: false
  [acceptance] call eval_exp[u==w].filter-none legacy-reads=0 resolved=1 answer=error bottom; alarms: none; singleton: false

The other evaluation families, unfiltered and on every stack. Since u == w
on each stack, the stacks agree on one callee, one cell of a, a divisor of
1 and no alarm; the joined state allows both callees, three cells, a
division by zero and an index out of bounds. s is initialized on the first
stack only.
  $ grep -e "\[100/((u-w)+1)\]\.unfiltered" -e "\[100/((u-w)+1)\]\.selector-all" -e "\[a\[u-w\]\]\.unfiltered" -e "\[a\[u-w\]\]\.selector-all" -e "\[s\]\.unfiltered" -e "\[s\]\.selector-all" -e "\[s\]\.stack:main/g@39" -e "eval_callee.*\.unfiltered" -e "eval_callee.*\.selector-all" -e "call callee.P" candidate.log
  [acceptance] call eval_exp[100/((u-w)+1)].unfiltered legacy-reads=0 resolved=1 answer={-100; 33; 50; 100}; alarms: Division_by_zero((u - w) + 1); singleton: false
  [acceptance] call expr_deps[100/((u-w)+1)].unfiltered legacy-reads=0 resolved=2 answer=u;; w
  [acceptance] call expr_dependencies[100/((u-w)+1)].unfiltered legacy-reads=0 resolved=2 answer=u;; w
  [acceptance] call eval_exp[a[u-w]].unfiltered legacy-reads=0 resolved=1 answer={0}; alarms: Index_out_of_bound(u - w >=; 0); singleton: true
  [acceptance] call expr_deps[a[u-w]].unfiltered legacy-reads=0 resolved=3 answer=u; w;; a[0..2]
  [acceptance] call expr_dependencies[a[u-w]].unfiltered legacy-reads=0 resolved=3 answer=u; w;; a[0..2]
  [acceptance] call eval_lval[a[u-w]].unfiltered legacy-reads=0 resolved=1 answer={0}; initialized: true; alarms: Index_out_of_bound(u - w >=; 0)
  [acceptance] call eval_address[a[u-w]].unfiltered legacy-reads=0 resolved=1 answer={{ a -> {0; 32; 64} }} (size:32); zone: a[0..2]; alarms: Index_out_of_bound(u - w >=; 0)
  [acceptance] call lval_deps[a[u-w]].unfiltered legacy-reads=0 resolved=3 answer=u; w;; a[0..2]
  [acceptance] call address_deps[a[u-w]].unfiltered legacy-reads=0 resolved=2 answer=u;; w
  [acceptance] call eval_exp[s].unfiltered legacy-reads=0 resolved=1 answer={5}; alarms: Uninitialized(s); singleton: true
  [acceptance] call expr_deps[s].unfiltered legacy-reads=0 resolved=1 answer=s
  [acceptance] call expr_dependencies[s].unfiltered legacy-reads=0 resolved=1 answer=s
  [acceptance] call eval_lval[s].unfiltered legacy-reads=0 resolved=1 answer={5} or UNINITIALIZED; initialized: false; alarms: none
  [acceptance] call eval_address[s].unfiltered legacy-reads=0 resolved=1 answer={{ s -> {0} }} (size:32); zone: s; alarms: none
  [acceptance] call lval_deps[s].unfiltered legacy-reads=0 resolved=1 answer=s
  [acceptance] call address_deps[s].unfiltered legacy-reads=0 resolved=0 answer=\nothing
  [acceptance] call eval_callee[*(tbl[u-w])].unfiltered legacy-reads=0 resolved=1 answer=f1 f2
  [acceptance] call eval_exp[s].stack:main/g@39 legacy-reads=0 resolved=1 answer={5}; alarms: none; singleton: true
  [acceptance] call expr_deps[s].stack:main/g@39 legacy-reads=0 resolved=1 answer=s
  [acceptance] call expr_dependencies[s].stack:main/g@39 legacy-reads=0 resolved=1 answer=s
  [acceptance] call eval_lval[s].stack:main/g@39 legacy-reads=0 resolved=1 answer={5}; initialized: true; alarms: none
  [acceptance] call eval_address[s].stack:main/g@39 legacy-reads=0 resolved=1 answer={{ s -> {0} }} (size:32); zone: s; alarms: none
  [acceptance] call lval_deps[s].stack:main/g@39 legacy-reads=0 resolved=1 answer=s
  [acceptance] call address_deps[s].stack:main/g@39 legacy-reads=0 resolved=0 answer=\nothing
  [acceptance] call eval_exp[100/((u-w)+1)].selector-all legacy-reads=0 resolved=1 answer={100}; alarms: none; singleton: true
  [acceptance] call expr_deps[100/((u-w)+1)].selector-all legacy-reads=0 resolved=2 answer=u;; w
  [acceptance] call expr_dependencies[100/((u-w)+1)].selector-all legacy-reads=0 resolved=2 answer=u;; w
  [acceptance] call eval_exp[a[u-w]].selector-all legacy-reads=0 resolved=1 answer={0}; alarms: none; singleton: true
  [acceptance] call expr_deps[a[u-w]].selector-all legacy-reads=0 resolved=3 answer=u; w;; a[0]
  [acceptance] call expr_dependencies[a[u-w]].selector-all legacy-reads=0 resolved=3 answer=u; w;; a[0]
  [acceptance] call eval_lval[a[u-w]].selector-all legacy-reads=0 resolved=1 answer={0}; initialized: true; alarms: none
  [acceptance] call eval_address[a[u-w]].selector-all legacy-reads=0 resolved=1 answer={{ a -> {0} }} (size:32); zone: a[0]; alarms: none
  [acceptance] call lval_deps[a[u-w]].selector-all legacy-reads=0 resolved=3 answer=u; w;; a[0]
  [acceptance] call address_deps[a[u-w]].selector-all legacy-reads=0 resolved=2 answer=u;; w
  [acceptance] call eval_exp[s].selector-all legacy-reads=0 resolved=1 answer={5}; alarms: Uninitialized(s); singleton: true
  [acceptance] call expr_deps[s].selector-all legacy-reads=0 resolved=1 answer=s
  [acceptance] call expr_dependencies[s].selector-all legacy-reads=0 resolved=1 answer=s
  [acceptance] call eval_lval[s].selector-all legacy-reads=0 resolved=1 answer={5} or UNINITIALIZED; initialized: false; alarms: none
  [acceptance] call eval_address[s].selector-all legacy-reads=0 resolved=1 answer={{ s -> {0} }} (size:32); zone: s; alarms: none
  [acceptance] call lval_deps[s].selector-all legacy-reads=0 resolved=1 answer=s
  [acceptance] call address_deps[s].selector-all legacy-reads=0 resolved=0 answer=\nothing
  [acceptance] call eval_callee[*(tbl[u-w])].selector-all legacy-reads=0 resolved=1 answer=f1
  [acceptance] call callee.P legacy-reads=0 resolved=1 answer=f1 f2

A supplied Cvalue state is the input of its evaluation, whatever the
selection: the model of the first stack with x = 7 gives x == y = 0, and
neither the store nor the resolver is read. Disabled domains keep their
response without reading either.
  $ grep -e "call eval_exp\[x==y\]\.supplied" -e "call eval_callee.*\.supplied" -e "call equality_class" -e "call is_tainted" candidate.log
  [acceptance] call eval_exp[x==y].supplied legacy-reads=0 resolved=0 answer={0}; alarms: none; singleton: true
  [acceptance] call eval_callee[*(tbl[u-w])].supplied legacy-reads=0 resolved=0 answer=f1
  [acceptance] call eval_exp[x==y].supplied-selected legacy-reads=0 resolved=0 answer={0}; alarms: none; singleton: true
  [acceptance] call eval_callee[*(tbl[u-w])].supplied-selected legacy-reads=0 resolved=0 answer=f1
  [acceptance] call equality_class[x==y] legacy-reads=0 resolved=0 answer=error disabled domain
  [acceptance] call is_tainted[x==y] legacy-reads=0 resolved=0 answer=error disabled domain

No request of the battery reads the legacy store, except the availability
readers and the snapshot export, whose states the hit log rebuilds: the
export reads the status table once, to copy the callers and analysis
status of each function.
  $ grep -e "^\[acceptance\] call" candidate.log | grep -v -e "legacy-reads=0 " | cut -d " " -f 3,4
  available.g legacy-reads=1
  status.g legacy-reads=1
  export.get_results legacy-reads=1

A fresh-only reference on the legacy path, in a separate process, gives
the same answers, the order of the stacks included.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance reference selection.i > reference.log 2>&1
  $ grep -e "^\[acceptance\] call" reference.log | sed -e "s/ legacy-reads=[^ ]* resolved=[^ ]*//" > reference-answers.txt
  $ grep -e "^\[acceptance\] call" candidate.log | sed -e "s/ legacy-reads=[^ ]* resolved=[^ ]*//" > candidate-answers.txt
  $ diff reference-answers.txt candidate-answers.txt
  $ wc -l < candidate-answers.txt
  473

In one process, the models, values, locations, zones, dependencies,
callees, alarms and stack lists of the reference and the candidate are
natively equal.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -inout-state-query-acceptance native selection.i > native.log 2>&1
  $ grep -e "equal=false" -e "native compared" native.log
  [acceptance] native compared=450 differing=0

Control: a resolver that rebuilds each visit from the first producer of g
gives every stack the state of the first call, and the requests on several
stacks or none follow it.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-no-memexec -inout-state-query-acceptance wrong-producer selection.i > wrong-producer.log 2>&1
  $ grep -e "call eval_exp\[x==y\]\.unfiltered" -e "call eval_exp\[x==y\]\.stack:main/g@43" -e "call by_callstack.unfiltered" wrong-producer.log
  [acceptance] call by_callstack.unfiltered legacy-reads=0 resolved=4 answer=main/g@40: {1} main/g@39: {1} main/g@43: {1}
  [acceptance] call eval_exp[x==y].unfiltered legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true
  [acceptance] call eval_exp[x==y].stack:main/g@43 legacy-reads=0 resolved=1 answer={1}; alarms: none; singleton: true

With a memexec hit, the resolver cannot rebuild the points below the hit
yet: it declines every request on several stacks or none, which reads the
legacy store. The singleton requests outside the hit stay on the resolver.
  $ frama-c -no-autoload-plugins -load-module eva,inout -eva-domains cvalue -eva-memexec -eva-msg-key progress -inout-state-query-acceptance candidate hit.i > hit.log 2>&1
  $ grep -e "Reusing" -e "call stacks.before-P" -e "call model.before-P" -e "visits f" hit.log
  [eva:progress] hit.i:16: Reusing old results for call to f
  [acceptance] call stacks.before-P legacy-reads=3 resolved=0 answer=main/f@13
  [acceptance] call model.before-P legacy-reads=2 resolved=0 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] call model.before-P.main/f@13 legacy-reads=0 resolved=1 answer=g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@13 body#1: 1 entries survive the preconditions; input:; g ∈ {4}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
  [acceptance] visits f.main/f@16 hit#1: no body analysis; input:; g ∈ {9}; y ∈ {0}; x ∈ {10}; __retres ∈ UNINITIALIZED
