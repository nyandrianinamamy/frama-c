/* run.config
   MODULE: @PTEST_NAME@
   STDOPT:
   STDOPT: +"-eva-no-hit-log"
*/

/* The states that the legacy store joins over the callstacks, and the reads
   of this store after the iteration. consolidation.ml turns
   Eva.Legacy_read_trap on before the analysis. It prints what the trap
   reports when the hook run when Eva has results starts, that is, what was
   read from the end of the iteration to that hook, then what it reports at
   the end of the analysis, by pass, and whether the legacy store holds a
   joined state before S.
   Expected: with -eva-hit-log, no read of the legacy store after the
   iteration, and no joined state. Without -eva-hit-log, no read before the
   hook; after it, the pass named consolidation reads the states of the two
   callstacks of f, outside any request, and stores their join. */

int g;

void f(int x) { S: g = x; }

int main(void) { f(1); f(2); return g; }
