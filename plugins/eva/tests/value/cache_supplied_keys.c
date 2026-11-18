/* run.config
   COMMENT: The test module supplies an entry with two exit states of
   COMMENT: different partition keys, then prints the entry.
   PLUGIN: eva
   MODULE: @PTEST_NAME@
   COMMENT: The partitioning of a callee is not kept through the return of a
   COMMENT: call: the two states are joined after the call.
   OPT: @EVA_OPTIONS@ -eva-msg-key cache
   COMMENT: The partitioning of a callee is kept through the return of a call:
   COMMENT: the two states stay apart after the call.
   OPT: @EVA_OPTIONS@ -eva-msg-key cache -eva-partition-path 1 -eva-interprocedural-partition-path
*/
/* run.config*
   DONTRUN: the reuse operation with supplied entries needs cvalue alone.
*/

/* The call to choose hits entry 1, whose exit states are out = 1 with the
   key of the first case of a disjunction at the return of choose, and
   out = 2 with the key of the second case. The keys go with the states: in
   the second run, Frama_C_show_each_after_choose prints the two states
   apart, {1} and {2}; in the first run, where the analysis drops the keys
   of a callee at its return, it prints {1; 2}. */

volatile int choice;
int out;

void choose(void) {
  if (choice) out = 1;
  else out = 2;
}

int main(void) {
  choose();
  Frama_C_show_each_after_choose(out);
  return 0;
}
