/* run.config
   MODULE: hit_log_observer @PTEST_NAME@
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main round_trip_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main fragments_main"
   STDOPT: +"-eva-no-alloc-returns-null -main renamed_main"
   STDOPT: +"-eva-no-alloc-returns-null -main multi_target_main"
   STDOPT: +"-eva-no-alloc-returns-null -main unreached_main"
   STDOPT: +"-eva-no-alloc-returns-null -main cycle_main"
*/

/* #124: numbered.ml prints the numbered form of each stored entry and checks
   its round trip. #125: memexec looks the calls up on this form. */

#include <stdlib.h>
#include <string.h>
#include "__fc_builtin.h"

/* Pointers to a strong and to a weak block, an escaping address and an
   uninitialised range, all in the block of c, which is in the key of
   read_cell. At i = 0, calloc creates a strong block; at i = 1, it reuses
   that block, still live, and makes it weak. */
struct cell { int *strong; int *weak; int *escaping; int uninit[2]; };

int read_cell(struct cell *c) { return *c->strong + *c->weak; }

/* The address of a local of the caller, written into an allocated block:
   the clobbered set of the call holds that block. */
void store(int **slot, int *addr) { *slot = addr; }

int r_cell;
void round_trip_main(void) {
  struct cell *c = malloc(sizeof *c);
  c->strong = malloc(sizeof(int));
  *c->strong = 1;
  for (int i = 0; i < 2; i++) c->weak = calloc(1, sizeof(int));
  { int dead = 0; c->escaping = &dead; }
  r_cell = read_cell(c);
  int local = 0;
  int **slot = malloc(sizeof *slot);
  store(slot, &local);
}

/* A whole pointer to a weak block, then two fragments of pointers to it,
   copied apart: the two halves of frag_slot are bound apart, since the
   block is weak. The inputs of the two calls of copy_slot differ by that. */
int *frag_slot, *frag_copy;
void copy_slot(void) { frag_copy = frag_slot; }

void fragments_main(void) {
  int *w = 0;
  for (int i = 0; i < 2; i++) w = calloc(1, sizeof(int));
  frag_slot = w;
  copy_slot();
  int *p1 = w, *p2 = w;
  frag_slot = 0; frag_copy = 0;
  memcpy(&frag_slot, &p1, 2);
  memcpy((char *)&frag_slot + 2, (char *)&p2 + 2, 2);
  copy_slot();
}

/* Two calls on two blocks of two sites, with the same strength, extent,
   type, kind and content: the second call is a hit. */
int sum(int *p) { return p[0] + p[1]; }

int r_sum[2];
void renamed_main(void) {
  int *a = malloc(2 * sizeof(int));
  a[0] = 1; a[1] = 2;
  int *b = malloc(2 * sizeof(int));
  b[0] = 1; b[1] = 2;
  r_sum[0] = sum(a);
  r_sum[1] = sum(b);
}

/* A pointer to two blocks, without slevel. The first call has a = 1 and
   b = 2, the second c = 2 and d = 1, where a, b, c, d are created in this
   order: the renaming from a to d and from b to c maps the first input to
   the second. */
int deref(int *p) { return *p; }

int r_deref[2];
void multi_target_main(void) {
  int *a = malloc(sizeof(int));
  *a = 1;
  int *b = malloc(sizeof(int));
  *b = 2;
  int *p = Frama_C_interval(0, 1) ? a : b;
  r_deref[0] = deref(p);
  int *c = malloc(sizeof(int));
  *c = 2;
  int *d = malloc(sizeof(int));
  *d = 1;
  int *q = Frama_C_interval(0, 1) ? c : d;
  r_deref[1] = deref(q);
}

/* An allocated block of the key that no value of the arguments or of the
   key points to, as in snapshot_key_block.c: the dependencies of
   \initialized(gp) replace the read of gp by the bits of the block (#97,
   case B3). The call of deref before it mentions another block. */
int *gp;
int unreached(void) {
  //@ assert \initialized(gp);
  return 7;
}

int r_unreached;
void unreached_main(void) {
  int *f = malloc(sizeof(int));
  *f = 5;
  r_deref[0] = deref(f);
  gp = calloc(1, sizeof *gp);
  r_unreached = unreached();
}

/* Two allocated blocks that point to each other, both in the key. */
struct node { struct node *next; int v; };
int second(struct node *n) { return n->next->v + n->next->next->v; }

int r_second;
void cycle_main(void) {
  struct node *a = malloc(sizeof *a);
  struct node *b = malloc(sizeof *b);
  a->next = b; a->v = 1;
  b->next = a; b->v = 2;
  r_second = second(a);
}
