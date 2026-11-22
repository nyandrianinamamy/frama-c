/* run.config
   STDOPT: +"-eva-unroll-recursive-calls 20"
*/

/* Starts of the calls below a hit that cross a recursion. A recursive call
   renames the variables of the outer call of its function whose address is
   taken, here x or y, to \copy<x>[d] or \copy<y>[d] at depth d, and rewrites
   the pointers to them, here the formal r of the call in between. The start
   state stored for a call below a hit does not replay this renaming.

   even_ptr(2) called by odd_ptr(3) called by even_ptr(4) is a hit of
   even_ptr(2) called by odd_ptr(3) called by main. Below it, odd_ptr(1) and
   even_ptr(0) are recursive calls, and set is called by even_ptr(0): their
   starts on these callstacks are unavailable, and so are the points of the
   body of set there, and the joined and filtered states that include these
   callstacks. Rebuilt from the stored start states, odd_ptr(1) would have r
   pointing to x where the run without memexec has &\copy<x>[1], and
   even_ptr(0) and set the copy \copy<y>[1] where it has \copy<y>[2].

   The second call even_ptr(4, &b) is a hit of the first one. Below it,
   odd_ptr(3) is not a recursive call: its start is answered. even_ptr(2) is
   a recursive call: its start is unavailable, as are those of the calls
   below it.

   The second call odd_ptr(1, &c) is a hit of the first one. Below it,
   even_ptr(0) and set are not recursive calls: their starts are answered. */

void even_ptr(unsigned int, int *);

void set(int *p, int v) { L: *p = v; }

void odd_ptr(unsigned int n, int *r) {
  if (n) { int x; even_ptr(n - 1, &x); *r = x; } else set(r, 0);
}

void even_ptr(unsigned int n, int *r) {
  if (n) { int y; odd_ptr(n - 1, &y); *r = y; } else set(r, 1);
}

int a, b, c;

int main(void) {
  odd_ptr(3, &a);
  even_ptr(4, &b);
  b = 0;
  even_ptr(4, &b);
  odd_ptr(1, &c);
  c = 0;
  odd_ptr(1, &c);
  return 0;
}
