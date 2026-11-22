/* run.config
   STDOPT:
*/

/* Starts of the calls below a hit that cross a recursion, with recursive
   calls analysed by their specification (the default setting). As with a
   recursive call analysed by its body, see unrolled_renaming.c, Eva renames
   the variables of the outer call of its function whose address is taken,
   here x to \copy<x>[1], and rewrites the pointers to them, here the formal
   p of g. The start state stored for a call below a hit does not replay this
   renaming.

   The second call f(&a) is a hit of the first one. Below it, g is not a
   recursive call: its start is answered. g calls f, a recursive call
   analysed by the specification of f that renames x: its start on this
   callstack is unavailable, and so are the joined and filtered starts of f
   that include this callstack. Rebuilt from the stored start state, it would
   have p pointing to x where the run without memexec has &\copy<x>[1].

   The points of g after the call f(p) are more precise than in the run
   without memexec, on both callstacks of g: InOut misses the write of the
   specification of f to x, known issue #103.

   The second call h(3) is a hit of the first one. Below it, k calls h, a
   recursive call analysed by the specification of h that renames no
   variable: the address of n is not taken, and the argument m - 1 is not an
   lvalue. Its start is answered. */

void g(int *p);

/*@ assigns *r \from \nothing; */
void f(int *r) { int x; F: g(&x); *r = x; }

void g(int *p) { f(p); }

void k(unsigned int m);

/*@ assigns \nothing; */
void h(unsigned int n) { k(n); }

void k(unsigned int m) { if (m) h(m - 1); }

int a;

void main(void) {
  f(&a);
  a = 0;
  f(&a);
  h(3);
  h(3);
}
