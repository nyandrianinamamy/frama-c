Storage is refused for a body that reads, writes or designates an allocated
block, that reads its validity or type, or whose analysis allocates, frees or
changes the validity of a block.

  $ dune build -j 8 --cache=disabled --root . test_allocation_refusals.cmxs

A copy of a pointer to an allocated block is refused, though no pointer is
dereferenced. An assertion alone designates the block. Each allocation effect
gives its own reason. The second call to scratch_once does not allocate: the
block of the first call is freed at the return.

  $ EVA_TEST_ALLOCATION=effects frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-slevel 4 -eva-msg-key cache -eva-statistics-file effects.tsv effects.c > effects.log 2>&1
  $ grep -E '^(copy|logic_only|allocate|resize|release|scratch|scratch_once|vla|main)[ :]' effects.log
  allocate allocation
  copy allocated-block
  logic_only: allocated-block allocation-metadata
  resize reallocation
  release deallocation
  scratch allocation
  scratch_once call 1 allocation
  scratch_once call 2 deallocation
  vla allocation
  main reallocation
  $ grep -E '; collector:' effects.log
    call to allocate: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocation)
    call to copy: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocated-block)
    call to logic_only: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocated-block)
    call to resize: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (reallocation)
    call to release: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (deallocation)
    call to scratch: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocation)
    call to scratch_once: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocation)
    call to scratch_once: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (deallocation)
    call to vla: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocation)
    call to main: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (reallocation)
  $ awk -F '\t' '/^collector-/ { print $1, $2, $4 }' effects.tsv
  collector-refused-allocated-block copy 1
  collector-refused-allocated-block logic_only 1
  collector-refused-allocation allocate 1
  collector-refused-allocation scratch 1
  collector-refused-allocation scratch_once 1
  collector-refused-allocation vla 1
  collector-refused-deallocation release 1
  collector-refused-deallocation scratch_once 1
  collector-refused-reallocation resize 1
  collector-refused-reallocation main 1

An integer loop whose widening visits an allocated binding is refused, and the
block is an owner although the loop does not access it. The same loop has no
owner before the allocation, and a loop that converges without widening is
not refused. A loop that writes to a weak block is refused for the update of
its validity by the widening, without any allocation.

  $ EVA_TEST_ALLOCATION=widening frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-mlevel 0 -eva-msg-key cache widening.c > widening.log 2>&1
  $ grep -E '^(shift|quiet|fill) ' widening.log
  shift before the allocation: no owner
  shift after the allocation: owners __malloc_main_l43
  quiet would-store
  fill validity-mutation
  $ grep -E 'call to (shift|quiet|fill):' widening.log
    call to shift: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (side-table)
    call to shift: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocation-metadata)
    call to quiet: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: would-store
    call to fill: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (validity-mutation)

The comparing function of the validity replay is refused.

  $ EVA_TEST_ALLOCATION=equality frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-slevel 20 -eva-no-alloc-returns-null -eva-msg-key cache equality.c > equality.log 2>&1
  $ grep -E '^equal_live |Frama_C_show_each_equal' equality.log
  equal_live allocated-block
  [eva:show] equality.c:21: Frama_C_show_each_equal: {0}, {1}
  equal_live allocated-block
  [eva:show] equality.c:21: Frama_C_show_each_equal: {1}, {0; 1}

Memexec stores the call to release and answers the second call by a hit; the
collector refuses each analysis of release, and the enclosing body inherits
the reason.

  $ EVA_TEST_ALLOCATION=release frama-c -no-autoload-plugins -load-module eva,inout,test_allocation_refusals.cmxs -eva -eva-memexec -eva-slevel 20 -eva-msg-key cache release.c > release.log 2>&1
  $ grep -E '^(release|main) |call to (release|main):' release.log
  release deallocation
    call to release: lookup: no-candidate; execution: analysed; storage: stored (entry 1); collector: refused (deallocation)
    call to release: lookup: hit (entry 1); execution: not-analysed; storage: none
  main allocation
    call to main: lookup: no-candidate; execution: analysed; storage: refused (not-cacheable); collector: refused (allocation)

The requires clauses of a body are checked at the call site, outside its
observation, but the allocated blocks and the allocation metadata they read
refuse the body.

  $ EVA_TEST_ALLOCATION=requires frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-msg-key cache requires.c > requires.log 2>&1
  $ grep -E '^(valid_only|initialized_only|length_only) |call to (valid_only|initialized_only|length_only):' requires.log
  valid_only allocated-block, owners __malloc_main_l18
    call to valid_only: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocated-block)
  initialized_only allocated-block, owners __malloc_main_l18
    call to initialized_only: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocated-block)
  length_only allocated-block, owners __malloc_main_l18
    call to length_only: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (allocated-block)

A load that combines a cell holding part of a pointer to an allocated block
with an uninitialized cell designates the block, in C and in a requires
clause checked at the call site. With an initialized padding, the combined
value designates it. A clause over a word without pointer is not refused.
The clauses add nothing to the reads of the body.

  $ EVA_TEST_ALLOCATION=call-site frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-no-alloc-returns-null -machdep x86_32 -eva-msg-key cache call-site.c > call-site.log 2>&1
  $ grep -E '^(c_word|req_word|req_initialized|req_plain) call' call-site.log
  req_word call 1: allocated-block
  req_initialized call 1: allocated-block allocation-metadata, owners __malloc_main_l32
  req_plain call 1: would-store
  c_word call 1: allocated-block

The string scans of requires clauses designate every cell of the blocks
they scan, at the call site as in a body. An unknown value refuses with
footprint-top, through a string scan or an initialization test. The scan
before the allocation is not refused.

  $ EVA_TEST_ALLOCATION=call-site frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-no-alloc-returns-null -eva-msg-key cache strings.c > strings.log 2>&1
  $ grep -E '^(scan|length|scan_unknown|initialized_unknown) call' strings.log
  scan call 1: would-store
  scan call 2: allocated-block
  length call 1: allocated-block
  scan_unknown call 1: footprint-top
  initialized_unknown call 1: footprint-top

A body that writes a part of a block whose other part holds part of a
pointer to an allocated block is refused, though it does not read the
pointer. The same writes to a block without pointer are not refused. A
body that reads a field beside a field holding such a pointer, without
reading the pointer, is not refused either: sibling records the current
verdict, and the pointer stays in the block of a produced key.

  $ EVA_TEST_ALLOCATION=contents frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-no-alloc-returns-null -eva-msg-key cache contents.c > contents.log 2>&1
  $ grep -E '^(partial|partial_once|control|sibling) call' contents.log
  partial call 1: allocated-block, owners __malloc_main_l41
  partial_once call 1: allocated-block, owners __malloc_main_l41
  control call 1: would-store
  sibling call 1: would-store

The automatic blocks of a call are freed by its caller when the call
returns. A call that never returns and the entry point free nothing.

  $ EVA_TEST_ALLOCATION=finalisation frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-slevel 4 -main no_return -eva-msg-key cache,malloc:automatic-free finalisation.c > no_return.log 2>&1
  $ grep -E '^(scratch|no_return) call|automatic bases' no_return.log
  scratch call 1: allocation deallocation builtin sweep contract nested-call allocated-block allocation-metadata, owners __alloca_scratch_l10
    freeing automatic bases: {__alloca_scratch_l10}
  scratch call 2: would-store
  no_return call 1: allocation deallocation sweep nested-call allocated-block allocation-metadata side-table, owners __alloca_scratch_l10
  $ EVA_TEST_ALLOCATION=finalisation frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -main entry -eva-msg-key cache finalisation.c > entry.log 2>&1
  $ grep -E '^entry call' entry.log
  entry call 1: allocation builtin contract nested-call allocated-block allocation-metadata, owners __alloca_entry_l26

On a memexec hit, the caller checks the requires clauses of the callee
again, with its own recording: hit_only is refused for the allocated block
and its metadata, though no body of leaf runs during its analysis.

  $ EVA_TEST_ALLOCATION=hit frama-c -no-autoload-plugins -load-module eva,inout,test_allocation_refusals.cmxs -eva -eva-memexec -eva-no-alloc-returns-null -eva-msg-key cache hit.c > hit.log 2>&1
  $ grep -E '^(leaf|warm|hit_only) call|call to (leaf|warm|hit_only):' hit.log
  leaf call 1: allocated-block allocation-metadata, owners __malloc_main_l16
    call to leaf: lookup: no-candidate; execution: analysed; storage: stored (entry 1); collector: refused (allocated-block)
  warm call 1: nested-call allocated-block allocation-metadata side-table, owners __malloc_main_l16
    call to warm: lookup: no-candidate; execution: analysed; storage: stored (entry 2); collector: refused (nested-call)
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
  hit_only call 1: nested-call allocated-block allocation-metadata side-table, owners __malloc_main_l16
    call to hit_only: lookup: no-candidate; execution: analysed; storage: stored (entry 3); collector: refused (nested-call)


After a block becomes weak, a body whose analysis compares states through
the partitioning index is refused, with the weakened block as owner. Before
the weakening, and for a body with one state at each point, it is not.

  $ EVA_TEST_ALLOCATION=weakening frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva -eva-no-memexec -eva-mlevel 0 -eva-slevel 4 -eva-msg-key cache weakening.c > weakening.log 2>&1
  $ grep -E '^(branch|straight|alloc) call' weakening.log
  branch call 1: would-store
  straight call 1: would-store
  alloc call 1: allocation builtin contract nested-call allocated-block allocation-metadata, owners __malloc_alloc_l10
  alloc call 2: allocation validity-mutation builtin contract nested-call allocated-block allocation-metadata, owners __malloc_w_alloc_l10
  alloc call 3: allocation validity-mutation builtin contract nested-call allocated-block allocation-metadata, owners __malloc_w_alloc_l10
  branch call 2: allocation-metadata, owners __malloc_w_alloc_l10
  straight call 2: would-store

An observer set in the kernel before a recording runs before, during and
after it; the collector records the read made during it. An observer set
during a recording is kept when the recording ends, and the collector
records the reads of the next recording. A second registration of an
allocated variable refuses a body that consults the node tags; its owner
is not known.

  $ EVA_TEST_ALLOCATION=kernel frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva-msg-key cache contents.c > kernel.log 2>&1
  $ grep -E '^(observer|tags)' kernel.log
  observer set before: runs 3, collector owners: observed
  observer set during: runs 3, kept true, owners: late; late, idle after: true
  tags: would-store, no owner
  tags: allocation-metadata, no owner

A validity record made weak through the kernel, without the allocation
builtins, refuses a body that consults the node tags. The weakening is
saved with the session: a node loaded by another process keeps the tag
computed while its target was strong, and the body is still refused.

  $ EVA_TEST_ALLOCATION=kernel-save frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva-msg-key cache contents.c -save kernel.sav > save.log 2>&1
  $ grep -E '^(loaded|tags)' save.log
  tags: would-store, no owner
  tags: allocation-metadata, no owner
  $ EVA_TEST_ALLOCATION=kernel-load frama-c -no-autoload-plugins -load-module eva,test_allocation_refusals.cmxs -eva-msg-key cache -load kernel.sav > load.log 2>&1
  $ grep -E '^(loaded|tags)' load.log
  loaded node tag: true
  tags: allocation-metadata, no owner
