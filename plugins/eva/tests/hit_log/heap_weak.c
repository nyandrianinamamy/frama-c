/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main m5 -eva-slevel 10"
*/

/* #119: a weak block whose extent a callee changes. The three calls of fr
   come from one call site: malloc allocates the block of the first call,
   then reuses it for the next ones, which makes it weak and resizes it to
   [0..11] at the third call. Before #119, the rule took this block from the
   body-entry state of fr at L5 and at every later point of fr, with its
   former extent [0..7]: the answer did not contain the reference. fr and m5
   are heap calls, and their answers are the full states of their bodies. */

#include <stdlib.h>
char *g; int z;
void fr(int n) { z = n; char *p = malloc(n); L5: ; z = 0; }
void m5(void) { for (int i = 1; i < 4; i++) { fr(4 * i); D: ; } E: ; }
