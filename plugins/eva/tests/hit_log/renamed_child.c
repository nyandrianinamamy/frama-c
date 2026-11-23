/* run.config
   MODULE: hit_log_observer renamed
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main child_main"
*/

/* #125: below a hit under a renaming, a call that used its own entry by
   identity uses it through the renaming of the hit, restricted to the
   blocks that its own entry mentions. leaf mentions no allocated block:
   below each hit of outer, it uses its entry by identity, and its members
   form one group, as before #125. half mentions the block of its argument
   only: below the hit of pair on b and e, it uses its entry through the
   pair d -> e of the renaming of the hit, without a -> b. */

#include <stdlib.h>

int leaf(void) { return 4; }
int outer(int *p) { return leaf() + *p; }

int half(int *q) { return *q; }
int pair(int *p, int *q) { return half(q) + *p; }

int r[6];
void child_main(void) {
  int *a = calloc(1, sizeof *a);
  int *b = calloc(1, sizeof *b);
  int *c = calloc(1, sizeof *c);
  int *d = calloc(1, sizeof *d);
  int *e = calloc(1, sizeof *e);
  r[0] = leaf();
  r[1] = outer(a);
  r[2] = outer(b);
  r[3] = outer(c);
  r[4] = pair(a, d);
  r[5] = pair(b, e);
}
