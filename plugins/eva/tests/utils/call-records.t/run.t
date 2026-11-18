With the category callstacks, each message of the category cache ends with
the callstack of the call, the called function first, and each call site is
followed by the number of its statement: the two calls to leaf on line 11
differ. The message of an analysed call follows those of the calls made by
its body, and the message of a hit is printed at the lookup. The headers of
the log end with a blank, removed before the messages are printed.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-records.c -eva-msg-key cache,callstacks -eva-statistics-file on.csv > on.log 2>&1
  $ sed -e 's/[[:blank:]]*$//' on.log > on.txt
  $ awk '/^\[/ { p = /^\[eva:cache\]/ } p' on.txt
  [eva:cache] call-records.c:11:
    call to leaf: lookup: no-candidate; execution: analysed; storage: stored (entry 1); collector: would-store
    stack: leaf :: call-records.c:11 (stmt 5) <-
           outer :: call-records.c:19 (stmt 12) <-
           main
  [eva:cache] call-records.c:11:
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
    stack: leaf :: call-records.c:11 (stmt 6) <-
           outer :: call-records.c:19 (stmt 12) <-
           main
  [eva:cache] call-records.c:19:
    call to outer: lookup: no-candidate; execution: analysed; storage: stored (entry 2); collector: refused (sweep)
    stack: outer :: call-records.c:19 (stmt 12) <- main
  [eva:cache] call-records.c:20:
    call to outer: lookup: hit (entry 2); execution: not-analysed; storage: none
    stack: outer :: call-records.c:20 (stmt 13) <- main
  [eva:cache] call-records.c:21:
    call to alloc: lookup: no-candidate; execution: analysed; storage: refused (not-cacheable); collector: refused (builtin)
    stack: alloc :: call-records.c:21 (stmt 14) <- main
  [eva:cache] call-records.c:22:
    call to alloc: lookup: no-candidate; execution: analysed; storage: refused (not-cacheable); collector: refused (builtin)
    stack: alloc :: call-records.c:22 (stmt 15) <- main
  [eva:cache]
    call to main: lookup: no-candidate; execution: analysed; storage: refused (not-cacheable); collector: refused (builtin)
    stack: main

The calls to malloc and free are answered by builtins and print no message
of the category cache. The statistics count each application of a builtin,
by the name under which it is selected for the called function.
  $ grep '^builtin-applied-' on.csv
  builtin-applied-free	free		2
  builtin-applied-malloc	malloc		2

Without the category callstacks, the messages have no callstack and no
statement number. With caching disabled, the builtins are applied as often.
  $ frama-c -no-autoload-plugins -load-module eva,inout,scope -eva call-records.c -eva-no-memexec -eva-msg-key cache -eva-statistics-file off.csv > off.log 2>&1
  $ grep -c 'eva:cache' off.log
  9
  $ grep -c 'stack:\|(stmt' off.log
  0
  [1]
  $ grep '^builtin-applied-' off.csv
  builtin-applied-free	free		2
  builtin-applied-malloc	malloc		2
