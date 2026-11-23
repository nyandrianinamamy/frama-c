/* run.config
   MODULE: hit_log_observer heap_rule
   STDOPT: +"-eva-no-alloc-returns-null -eva-unroll-recursive-calls 2 -main every_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-unroll-recursive-calls 2 -eva-slevel 10 -main stale_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-unroll-recursive-calls 2 -eva-slevel 10 -main stale_cond_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-unroll-recursive-calls 2 -main restored_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-unroll-recursive-calls 2 -eva-slevel 10 -main guarded_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main release_main"
*/

/* #122: the sweep map of the heap calls, on cells that the footprint of the
   call does not cover. Each run is compared by the observer with the run
   without memexec, and heap_rule.ml prints, at each labelled statement of
   each heap call, the blocks that the Inner part covers, those of them that
   it does not bind, and the blocks swept on every path and on some path
   only. A recursive call renames the variables of the outer call whose
   address is taken (here, saved), and the footprint of a call does not cover
   these renamed variables. It withdraws the other variables of the outer
   call (here, hidden) from the state, and puts them back at its end. */

#include <stdlib.h>
#include <alloca.h>
#include "__fc_builtin.h"
char *p, *g, *stale, **keep; int z;

/* The renamed saved of the outer call of recur points to the block that
   leaf frees: only the sweep map turns it into an escaping address in the
   answers of leaf. */
void leaf(void) { free(p); E: z++; }
void recur(int n) {
  char *saved = p;
  if (n) { keep = &saved; recur(0); } else leaf();
}
void every_main(void) { p = malloc(8); recur(1); }

/* withdraw(0) frees the block of p while withdraw(1) keeps a pointer to it
   in hidden, which the recursive call withdraws and puts back unswept:
   stale then points to a block that the state does not bind. The second
   call of worker allocates this block again and frees it, which sweeps the
   pointer in the renamed saved of the outer call of recur_stale, though the
   body-entry state of worker does not bind the block. */
void withdraw(int n) {
  char *hidden = p;
  if (n) { withdraw(0); stale = hidden; } else free(p);
}
void worker(int second) { p = malloc(8); if (second) free(p); F: z++; }
void recur_stale(int n, int second) {
  char *saved = stale;
  if (n) { keep = &saved; recur_stale(0, second); } else worker(second);
}
void stale_main(void) {
  for (int i = 0; i < 2; i++) { recur_stale(1, i); if (!i) withdraw(1); }
}

/* As above, but the second call of cond_worker allocates and frees the
   block on one path only: at C, the block is bound on no path, and the
   pointer to it in the renamed saved is swept on the other path only. */
void cond_worker(int second) {
  if (!second || Frama_C_interval(0, 1)) {
    p = malloc(8);
    if (second) free(p);
  }
  C: z++;
}
void recur_cond(int n, int second) {
  char *saved = stale;
  if (n) { keep = &saved; recur_cond(0, second); } else cond_worker(second);
}
void stale_cond_main(void) {
  for (int i = 0; i < 2; i++) { recur_cond(1, i); if (!i) withdraw(1); }
}

/* rf(0) frees the block of p, in a recursive call made by rh, under rg.
   The call withdraws hidden of rf(1) and puts it back unswept: at H and at
   G, hidden still points to the freed block. */
void rf(int n);
void rh(int n) { rf(n - 1); H: z++; }
void rg(int n) { rh(n); G: z++; }
void rf(int n) {
  char *hidden = p;
  if (n) { rg(n); stale = hidden; } else free(p);
}
void restored_main(void) { p = malloc(8); rf(1); }

/* Every state that reaches GU has freed the block of x: the other path does
   not terminate. The paths of the analysis join before the second test, and
   the block is swept on some path only on them. As the state at GU does not
   bind the block, which the body-entry state binds, the block is swept on
   every path there, and at the return of guarded, which mid receives. The
   loop, which only the states that did not free the block reach, still has
   the block swept on some path only: its answers cover those of the run
   without memexec. */
void guarded(char *x, int c) {
  if (c) free(x);
  if (!c) for (;;) {}
  GU: z++;
}
void mid(void) { guarded(p, Frama_C_interval(0, 1)); MI: z++; }
void recur_guarded(int n) {
  char *saved = p;
  if (n) { keep = &saved; recur_guarded(n - 1); } else mid();
}
void guarded_main(void) { p = malloc(8); recur_guarded(1); }

/* The call of al is evaluated in two states. The automatic release of the
   block of alloca, at the end of each evaluation, sweeps it on every path
   of this evaluation: the block is swept on every path at A. */
void al(int n) { char *a = alloca(n); a[0] = 1; g = a; }
void release(int c) {
  int n;
  if (c) n = 4; else n = 8;
  al(n);
  A: z++;
}
void release_main(void) { release(Frama_C_interval(0, 1)); }
