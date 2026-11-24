/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main calloc_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main realloc_main"
   STDOPT: +"-eva-no-alloc-returns-null -main alloca_main"
   STDOPT: +"-eva-no-alloc-returns-null -main vla_main"
   STDOPT: +"-eva-no-alloc-returns-null -main free_main"
*/

/* #119: the heap calls made through each allocation builtin, and through a
   free reached only by a callee two calls down. Every call that runs an
   allocation builtin or free, in its body or in a call nested in it, is a
   heap call. Memexec stores the calls that free and those that allocate
   with these builtins under the policy by_stack (#126 to #130). */

#include <stdlib.h>
#include <alloca.h>
char *g; int z;

/* calloc, twice from one call site: the second call reuses the block of the
   first one, which becomes weak and grows. */
void cz(int n) { z = n; g = calloc(n, 1); C: ; z = 0; }
void calloc_main(void) { for (int i = 1; i < 3; i++) { cz(4 * i); D: ; } }

/* realloc of a block allocated by the caller: the old block is freed. */
void rz(int n) { z = n; g = realloc(g, n); R: ; z = 0; }
void realloc_main(void) {
  g = malloc(2); if (!g) return; g[0] = 1;
  rz(4); E: ;
}

/* alloca: the block is released when az returns, in its caller. */
void az(void) { char *p = alloca(4); p[0] = 1; z = p[0]; A: ; }
void alloca_main(void) { z = 0; az(); B: ; }

/* A variable-length array, allocated and released in vz. */
void vz(int n) { char a[n]; a[0] = 1; z = a[0]; V: ; }
void vla_main(void) { vz(4); W: ; }

/* free reached from top through two calls: top never reads nor writes the
   block of q, and the block does not exist at T. */
void f1(char *p) { free(p); }
void f2(char *p) { f1(p); }
void top(char *p) { z = 1; f2(p); T: ; }
void free_main(void) {
  char *q = malloc(4); if (!q) return; q[0] = 7; g = q;
  top(q); F: ;
}
