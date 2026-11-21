/* run.config
   STDOPT: +"-main nested"
   STDOPT: +"-main second_case"
*/

/* Calls below a hit. */

#include "__fc_builtin.h"

int c, g, h, k;

/* The nested example of #87. The second call of f is a hit; the third is
   analysed. leaf is called below the hit: its points are unavailable on
   every callstack and without callstack. The answers inside f are those of
   the run without memexec. */
void leaf(int *p) { if (c) *p = k; Q: *p = *p + 1; }

void f(void) { int x; if (c) g = 0; x = g; P: leaf(&x); g = x; }

void nested(void) {
  c = Frama_C_interval(0, 1); k = 3;
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
}

/* A function reached only through a child that was itself a hit while the
   cache entry of the parent was computed: the call of child in the first
   call of parent is a hit of the first call of child, which called gc. gc
   is marked when parent is hit, as child is. */
int n;

void gc(void) { P: n = n + 1; }

void child(void) { gc(); }

void parent(void) { child(); P: ; }

void second_case(void) {
  n = 0; child();
  n = 0; h = 7; parent();
  n = 0; h = 8; parent();
}
