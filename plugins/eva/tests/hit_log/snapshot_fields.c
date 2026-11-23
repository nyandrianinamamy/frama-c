/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main record_main -eva-undefined-pointer-comparison-propagate-all"
   STDOPT: +"-eva-no-alloc-returns-null -main type_main -eva-widening-delay 1"
*/

/* #123: each field of the snapshot of a block decides a miss alone. In
   each run, the second compared call has the same arguments and key as the
   one before, and one field of the block it mentions differs: the validity
   record in run 0, the type in run 1. The strength does so in
   snapshot.c. The kind of a block never changes. */

#include <stdlib.h>
#include "__fc_builtin.h"

/* The record alone. One site allocates 8 bytes, then 6, then 4, and frees
   the block each time: it stays strong. The allocation of 6 bytes resizes
   it, which makes its type char[]; the allocation of 4 bytes lowers its
   record again, and its type stays char[]. p + 6 points beyond the bytes
   sure to be valid only at the last call. */
int cmp_r(char *p) { R: return p == 0; }

int r_record[3];
void record_main(void) {
  for (int i = 0; i < 3; i++) {
    char *p = malloc(8 - 2 * i);
    if (i) r_record[i] = cmp_r(p + 6);
    free(p);
  }
}

/* The type alone. At i = 0, malloc creates a strong block of type int[1];
   at i = 1, it reuses the block, still live, and makes it weak; the inner
   loop then writes a new value into the weak block, and its widening raises
   the record of the block to the largest size. At i = 2, malloc reuses the
   block with the same size: its record and strength do not change, and its
   type becomes int[]. */
int cmp_t(int *q) { T: return q == 0; }

int *p_type;
int r_type[3];
void type_main(void) {
  //@ loop unroll 3;
  for (int i = 0; i < 3; i++) {
    p_type = malloc(sizeof(int));
    while (Frama_C_interval(0, 1)) *p_type = 7 + i;
    r_type[i] = cmp_t(p_type);
  }
}
