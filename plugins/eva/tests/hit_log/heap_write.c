/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main write_main"
   STDOPT: +"-eva-no-alloc-returns-null -main lost_main -eva-slevel 10"
*/

/* #119: the calls that are not heap calls; #126: a call that frees, which
   memexec stores again. */

#include <stdlib.h>
char *g; int z;

/* w reads and writes the block that its caller allocated, and neither
   allocates nor frees: it is not a heap call, and the rule gives its
   answers. Its two calls have the same inputs: the second one is a hit.
   write_main allocates: it is a heap call. */
void w(char *p) { p[1] = p[0]; W: z = p[1]; }
void write_main(void) {
  char *q = malloc(4); if (!q) return; q[0] = 7;
  q[1] = 0; z = 0; w(q);
  q[1] = 0; z = 0; w(q);
  X: ;
}

/* release frees the block of g. The two calls of malloc come from one call
   site: the second one reuses the block that release freed, so that the two
   calls of release have the same inputs. From #119 to #126, memexec did not
   store release, a heap call, and the second call was analysed. Since #126,
   release is a call that frees: memexec stores it, and the second call is a
   hit, which removes the block of g and sweeps the pointers to it. */
void release(void) { free(g); g = 0; R: ; }
void lost_main(void) {
  for (int i = 0; i < 2; i++) { g = malloc(4); release(); N: ; }
}
