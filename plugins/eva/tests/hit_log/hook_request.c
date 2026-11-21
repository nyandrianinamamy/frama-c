/* run.config
   MODULE: hit_log_observer @PTEST_NAME@
   STDOPT:
*/

/* A request made outside the passes of Eva, by a hook run when Eva has
   results. hook_request.ml registers this hook: its request goes through a
   filter of the callstacks that reads the joined state of the legacy store
   before P, as a request served from that store would. The second call of f
   is a hit of the first.
   Expected: the observer reports this request outside the passes, with its
   read, in the analysis with memexec and in the analysis with
   -eva-hit-log. */

int g;

void f(void) { P: g++; }

int main(void) { f(); g = 0; f(); return g; }
