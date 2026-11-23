/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main weak_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main resized_main -eva-undefined-pointer-comparison-propagate-all"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main unchanged_main"
*/

/* #123: a call that receives no heap effect is matched with the snapshot
   of the allocated blocks it mentions: their strength, validity record,
   type and kind, as they were when its cache entry was stored. The blocks
   are those of its key, and those that a pointer value of its arguments or
   of its key points to. The functions below compare pointers and
   dereference none: the blocks they mention are not in their keys, and the
   content of the state that memexec compares is the same at each of their
   calls. */

#include <stdlib.h>

char *gp;

/* The block is mentioned through the arguments. */
int cmp(char *p, char *q) { P: return p == q; }

/* The block is mentioned through the value of gp, a block of the key. */
int cmp_global(char *q) { G: return gp == q; }

/* The block becomes weak. At i = 0, the call of malloc creates a strong
   block; at i = 1, it reuses that block, still live, and makes it weak. The
   arguments and the key are the same at both iterations: before #123,
   memexec reused the first calls of cmp and cmp_global for the second ones,
   which then compared a weak block as if it were strong (#94, case 1). */
int r_weak[2], r_weak_global[2];
void weak_main(void) {
  char *first = 0;
  for (int i = 0; i < 2; i++) {
    char *b = malloc(1);
    if (i == 0) { first = b; gp = b; }
    r_weak[i] = cmp(first, b);
    r_weak_global[i] = cmp_global(b);
  }
}

/* The block is resized. At i = 0, malloc creates a strong block of 8
   bytes; free removes it; at i = 1, malloc reuses it with 4 bytes: it
   stays strong, and its validity record becomes the join of the two sizes,
   so that only its first 4 bytes are sure to be valid. b + 6 is a valid
   pointer at i = 0, and at i = 1 it points beyond the bytes sure to be
   valid: its comparison raises an alarm, and with option
   -eva-undefined-pointer-comparison-propagate-all its result is {0; 1}
   rather than {0}. */
int r_resized[2];
void resized_main(void) {
  for (int i = 0; i < 2; i++) {
    char *b = malloc(i ? 4 : 8);
    r_resized[i] = cmp(b + 6, 0);
    free(b);
  }
}

/* Nothing changes between the two calls of each function: the second ones
   are hits. */
int r_unchanged[2], r_unchanged_global[2];
void unchanged_main(void) {
  char *b = malloc(8);
  gp = b;
  r_unchanged[0] = cmp(b + 6, 0);
  r_unchanged_global[0] = cmp_global(b);
  r_unchanged[1] = cmp(b + 6, 0);
  r_unchanged_global[1] = cmp_global(b);
}
