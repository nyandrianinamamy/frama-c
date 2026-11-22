/* run.config
   EXIT: 1
   STDOPT:
*/

/* The initialization of the globals fails: the analysis does not start, and
   no state is recorded. As without recording, the initial state is
   unavailable, not unreachable. */

int g = 1 << 40;

int main(void) { return g; }
