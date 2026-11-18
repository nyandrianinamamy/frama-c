The produced entry keeps the filtered key, all four access sets, the return
slot and the body call mode. Memexec still answers the second call.

  $ dune build -j 8 --cache=disabled --root . test_cache_producer.cmxs
  $ frama-c -no-autoload-plugins -load-module eva,inout,test_cache_producer.cmxs -eva -eva-msg-key cache producer.c > producer.log 2>&1
  $ grep -E '^leaf:|call to leaf: lookup: hit' producer.log
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
  leaf: key __retres,p,q; writes out and both return blocks; used leaf (body)

Supply the first fresh exit explicitly in a fixture analysis. The second
call hits the same key with keep=42 instead of keep=0. Compare the entire
caller model after the second call against a fresh run.

  $ EVA_TEST_CACHE_PRODUCER=replay frama-c -no-autoload-plugins -load-module eva,test_cache_producer.cmxs -eva-msg-key cache producer.c > replay.log 2>&1
  $ grep -E 'call to leaf: lookup: hit|^same full caller state' replay.log
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
    call to leaf: lookup: hit (entry 1); execution: not-analysed; storage: none
  same full caller state after replay: answer=2 keep=42 out=7

A partial overwrite needs the rest of its block in the input.

  $ EVA_TEST_CACHE_PRODUCER=partial frama-c -no-autoload-plugins -load-module eva,test_cache_producer.cmxs -eva -main partial producer.c > partial.log 2>&1
  $ grep '^partial:' partial.log
  partial: pair is in the key and is not a sure write

A two-block read exceeds a one-block limit. An otherwise eligible body
cannot store with both cvalue and sign active.

  $ frama-c -no-autoload-plugins -load-module eva -eva -main two_blocks -eva-cache-key-limit 1 -eva-msg-key cache-producer -eva-statistics-file limit.tsv producer.c > limit.log 2>&1
  $ grep 'call to two_blocks' limit.log
    call to two_blocks: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store; producer: refused (key-limit)
  $ awk -F '\t' '/^cache-production-/ { print $1, $2, $4 }' limit.tsv
  cache-production-refused-key-limit two_blocks 1
  $ frama-c -no-autoload-plugins -load-module eva -eva -main two_blocks -eva-cache-key-limit 2 -eva-msg-key cache-producer producer.c > at-limit.log 2>&1
  $ grep -o 'producer: stored (entry 1)' at-limit.log
  producer: stored (entry 1)
  $ frama-c -no-autoload-plugins -load-module eva -eva -main two_blocks -eva-domains cvalue,sign -eva-msg-key cache-producer producer.c > product.log 2>&1
  $ grep -o 'producer: refused (product)' product.log
  producer: refused (product)

The cvalue overlay cannot restore the absence of a block that left scope.
The precondition check runs outside the collector and may narrow a state.

  $ frama-c -no-autoload-plugins -load-module eva -eva -main inner_scope -eva-msg-key cache-producer producer.c > scope.log 2>&1
  $ grep -o 'collector: would-store; producer: refused (exit-binding)' scope.log
  collector: would-store; producer: refused (exit-binding)
  $ frama-c -no-autoload-plugins -load-module eva -eva -main swept -eva-msg-key cache-producer producer.c > swept.log 2>&1
  $ grep -o 'collector: refused (sweep); producer: refused (sweep)' swept.log
  collector: refused (sweep); producer: refused (sweep)
  $ frama-c -no-autoload-plugins -load-module eva -eva -main precondition -eva-msg-key cache-producer producer.c > precondition.log 2>&1
  $ grep -o 'collector: would-store; producer: refused (preconditions)' precondition.log
  collector: would-store; producer: refused (preconditions)
