With caching disabled, each call is analysed and its storage is refused.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-cache.c -eva-no-memexec -eva-msg-key cache -eva-statistics-file stats.csv > off.log 2>&1
  $ grep -A1 'eva:cache' off.log
  [eva:cache] call-cache.c:14: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (disabled)
  [eva:cache] call-cache.c:15: 
    call to leaf: lookup: no-candidate; execution: analysed; storage: refused (disabled)
  --
  [eva:cache] call-cache.c:16: 
    call to divide: lookup: no-candidate; execution: analysed; storage: refused (disabled)
  [eva:cache] 
    call to main: lookup: no-candidate; execution: analysed; storage: refused (disabled)

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
    call to leaf: lookup: no-candidate; execution: analysed; storage: stored (entry 1)
  [eva:cache] call-cache.c:15: 
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
  --
  [eva:cache] call-cache.c:16: 
    call to divide: lookup: no-candidate; execution: interrupted; storage: none
  [eva:cache] 
    call to main: lookup: no-candidate; execution: interrupted; storage: none
