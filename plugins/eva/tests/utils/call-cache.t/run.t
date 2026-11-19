With caching disabled, each call is analysed and its storage is refused.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-cache.c -eva-no-memexec -eva-msg-key cache -eva-statistics-file stats.csv > off.log 2>&1
  $ grep -A1 'eva:cache' off.log
  [eva:cache] call-cache.c:14: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: would-store
  [eva:cache] call-cache.c:15: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: would-store
  --
  [eva:cache] call-cache.c:16: 
    call to divide: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (callback)
  [eva:cache] 
    call to main: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (sweep)

No cache was consulted, so the statistics count nothing for memexec.
  $ grep -c '^memexec-' stats.csv
  0
  [1]

A call whose analysis is stopped by the first alarm is reported as interrupted,
and so is its caller. The analysis ends as it does without the category.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-cache.c -eva-stop-at-nth-alarm 1 > abort-quiet.log 2>&1
  [1]
  $ tail -n 1 abort-quiet.log
  [kernel] Plug-in eva aborted: invalid user input.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-cache.c -eva-stop-at-nth-alarm 1 -eva-msg-key cache > abort.log 2>&1
  [1]
  $ tail -n 1 abort.log
  [kernel] Plug-in eva aborted: invalid user input.
  $ grep -A1 'eva:cache' abort.log
  [eva:cache] call-cache.c:14: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: stored (entry 1); collector: would-store
  [eva:cache] call-cache.c:15: 
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
  --
  [eva:cache] call-cache.c:16: 
    call to divide: lookup: no-candidate; execution: interrupted; storage: none
  [eva:cache] 
    call to main: lookup: no-candidate; execution: interrupted; storage: none

Without the Inout plug-in, memexec has no footprint for a call and refuses
each storage; the second call to leaf finds no entry and is analysed.
  $ frama-c -no-autoload-plugins -load-module eva -eva call-cache.c -eva-msg-key cache -eva-statistics-file no-inout.csv > no-inout.log 2>&1
  $ grep -A1 'eva:cache' no-inout.log
  [eva:cache] call-cache.c:14: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
  [eva:cache] call-cache.c:15: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
  --
  [eva:cache] call-cache.c:16: 
    call to divide: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
  [eva:cache] 
    call to main: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (sweep)
  $ grep '^memexec-' no-inout.csv
  memexec-misses	leaf		2
  memexec-misses	divide		1
  memexec-misses	main		1
  memexec-refused-no-inout	leaf		2
  memexec-refused-no-inout	divide		1
  memexec-refused-no-inout	main		1

The printer domain relates every block to an unknown set of blocks, so each
storage is refused.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-cache.c -eva-domains printer -eva-msg-key cache -eva-statistics-file relate-top.csv > relate-top.log 2>&1
  $ grep -A1 'eva:cache' relate-top.log
  [eva:cache] call-cache.c:14: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (relate-top); collector: refused (side-table)
  --
  [eva:cache] call-cache.c:15: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (relate-top); collector: refused (side-table)
  --
  [eva:cache] call-cache.c:16: 
    call to divide: lookup: no-candidate; execution: analysed; storage: refused (relate-top); collector: refused (callback)
  --
  [eva:cache] 
    call to main: lookup: no-candidate; execution: analysed; storage: refused (relate-top); collector: refused (sweep)
  $ grep '^memexec-' relate-top.csv
  memexec-misses	leaf		2
  memexec-misses	divide		1
  memexec-misses	main		1
  memexec-refused-relate-top	leaf		2
  memexec-refused-relate-top	divide		1
  memexec-refused-relate-top	main		1
