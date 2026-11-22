/* run.config
   STDOPT: +"-main mutual -eva-unroll-recursive-calls 20"
   STDOPT: +"-main direct_ptr -eva-unroll-recursive-calls 20"
   EXIT: 1
   STDOPT: +"-main mutual -eva-unroll-recursive-calls 2"
*/

/* Starts of the calls below a hit, with unrolled recursive calls. The points
   of the bodies of the recursive functions are unavailable. Below a hit, a
   recursive call and the calls below it cross a recursion: their starts are
   unavailable, see unrolled_renaming.c. A recursive call removes the formals
   and locals of the outer call of its function, or renames them when their
   address is taken; the start state stored for the call replaces them. */

/* even(4) calls odd(3), a hit of the call made by mutual. Below it, even(2)
   is a recursive call: its start and those of odd(1) and even(0) below it
   are unavailable on these callstacks, and answered on the others.
   With -eva-unroll-recursive-calls 2, the run without memexec reaches even(0)
   at depth 2 below even(4), and uses a generated specification for it; the
   hit reuses the call made by mutual, within the bound. The answers after
   the call of even(4) are then more precise than the reference, as with
   memexec (the converse of #95). */
int even(unsigned int);

int odd(unsigned int n) { P: if (n) return even(n - 1); else return 0; }

int even(unsigned int n) { P: if (n) return odd(n - 1); else return 1; }

int a, b;

void mutual(void) {
  a = odd(3);
  b = even(4);
}

/* A direct recursion with locals passed by address. At each recursive call,
   the locals of the outer call are renamed and its formals p and r are
   removed. The hits are calls at the same depth as their cache entry, on
   another branch of the recursion: the calls below them cross a recursion. */
void fib(unsigned int *p, unsigned int *r) {
  if (*p < 2) *r = *p;
  else {
    unsigned int x, y;
    unsigned int m = *p;
    m--;
    fib(&m, &x);
    m--;
    fib(&m, &y);
    *r = x + y;
  }
}

void direct_ptr(void) {
  unsigned int n = 6, res;
  fib(&n, &res);
}
