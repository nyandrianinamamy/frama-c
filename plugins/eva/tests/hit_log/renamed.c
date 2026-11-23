/* run.config
   MODULE: hit_log_observer
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main equal_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main strength_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main extent_main -eva-undefined-pointer-comparison-propagate-all"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main type_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main kind_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main compare_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main escape_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main below_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main composed_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main joined_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main differ_main"
*/

/* #125: a call without heap effects that mentions an allocated block is
   reused on other blocks with equal content and equal snapshot, through a
   renaming. In each run, the blocks of the calls are made at distinct
   sites and stay live, so that a hit on them is a hit under a renaming
   that is not the identity. */

#include <stdlib.h>
#include <alloca.h>

int get(int *p) { G: return *p; }

/* Run 0: two blocks with equal content, strength, extent, type and kind.
   The second call of get is a hit. */
int r_get[4];
void equal_main(void) {
  int *a = malloc(sizeof(int));
  *a = 7;
  int *b = malloc(sizeof(int));
  *b = 7;
  r_get[0] = get(a);
  r_get[1] = get(b);
}

/* Run 1: the strength alone differs. The block of w is weak: calloc reuses
   it, still live, at i = 1. Both blocks hold zeroes on 4 bytes. */
void strength_main(void) {
  int *w = 0;
  for (int i = 0; i < 2; i++) w = calloc(1, sizeof(int));
  int *s = calloc(1, sizeof(int));
  r_get[0] = get(w);
  r_get[1] = get(s);
}

/* Run 2: the extent alone differs. Each site allocates 8 bytes, frees the
   block, then allocates it again with fewer bytes: the block stays strong,
   its type becomes char[], and its validity record joins the two sizes.
   The first 4 bytes of the block of a are sure to be valid, the first 6
   of that of b: a + 6 points beyond them, b + 6 does not. The contents
   are uninitialised on 8 bytes. */
int cmp(char *p) { C: return p == 0; }

int r_cmp[4];
void extent_main(void) {
  char *a = 0, *b = 0;
  for (int i = 0; i < 2; i++) {
    a = malloc(i ? 4 : 8);
    if (!i) free(a);
  }
  for (int i = 0; i < 2; i++) {
    b = malloc(i ? 6 : 8);
    if (!i) free(b);
  }
  r_cmp[0] = cmp(a + 6);
  r_cmp[1] = cmp(b + 6);
}

/* Run 3: the type alone differs: int[2] and char[8]. */
int cmp_void(void *p) { V: return p == 0; }

int r_void[2];
void type_main(void) {
  int *a = malloc(8);
  char *b = malloc(8);
  r_void[0] = cmp_void(a);
  r_void[1] = cmp_void(b);
}

/* Run 4: the kind alone differs: malloc and alloca. */
void kind_main(void) {
  char *a = malloc(8);
  char *b = alloca(8);
  r_void[0] = cmp_void(a);
  r_void[1] = cmp_void(b);
}

/* Run 5: pointers to allocated blocks that are compared and never
   dereferenced: the blocks are mentioned through the arguments, or through
   gp, a block of the key, and not in the keys. The second call of each
   pair is a hit; the last call of same swaps the two blocks. */
char *gp;
int same(char *p, char *q) { S: return p == q; }
int same_global(char *q) { H: return gp == q; }

int r_same[4], r_same_global[2];
void compare_main(void) {
  char *a = malloc(1);
  char *b = malloc(1);
  r_same[0] = same(a, a);
  r_same[1] = same(b, b);
  r_same[2] = same(a, b);
  r_same[3] = same(b, a);
  gp = a;
  r_same_global[0] = same_global(a);
  gp = b;
  r_same_global[1] = same_global(b);
}

/* Run 6: store writes the address of a local of its caller into an
   allocated block. The second call is a hit. When the scope of local ends,
   both blocks hold an escaping address: the clobbered set of the second
   call names the block of e2. */
void store(int **slot, int *addr) { *slot = addr; }

int **e1, **e2;
void after(void) { A: ; }

void escape_main(void) {
  e1 = malloc(sizeof *e1);
  e2 = malloc(sizeof *e2);
  {
    int local = 1;
    store(e1, &local);
    store(e2, &local);
  }
  after();
}

/* Run 7: outer calls inner. The second call of outer is a hit; the start
   of the call of inner below it points to the block of b. */
int inner(int *p) { I: return *p; }
int outer(int *p) { O: return inner(p); }

int r_outer[2], r_inner;
void below_main(void) {
  int *a = malloc(sizeof(int));
  *a = 3;
  int *b = malloc(sizeof(int));
  *b = 3;
  r_outer[0] = outer(a);
  r_outer[1] = outer(b);
}

/* Run 8: as run 7, after a first call of inner on c. In the analysed call
   of outer, the call of inner is a hit of the entry of inner(c) on a;
   below the hit of outer on b, the call of inner uses that entry on b. */
void composed_main(void) {
  int *c = malloc(sizeof(int));
  *c = 3;
  int *a = malloc(sizeof(int));
  *a = 3;
  int *b = malloc(sizeof(int));
  *b = 3;
  r_inner = inner(c);
  r_outer[0] = outer(a);
  r_outer[1] = outer(b);
}

/* Run 9: hits with different renamings, on two callstacks and twice on one
   callstack. A request without callstack joins them. */
void joined_main(void) {
  int *a = malloc(sizeof(int));
  *a = 7;
  int *b = malloc(sizeof(int));
  *b = 7;
  int *c = malloc(sizeof(int));
  *c = 7;
  int *t[2] = { b, c };
  r_get[0] = get(a);
  r_get[1] = get(b);
  r_get[2] = get(c);
  for (int i = 0; i < 2; i++) r_get[3] = get(t[i]);
}

/* Run 10: as run 8, with another content in the block of b. The inputs of
   the call of outer on a hold the block a, which the call of inner below it
   reads through the renaming of the entry of inner(c): the call of outer on
   b misses. */
void differ_main(void) {
  int *c = malloc(sizeof(int));
  *c = 3;
  int *a = malloc(sizeof(int));
  *a = 3;
  int *b = malloc(sizeof(int));
  *b = 4;
  r_inner = inner(c);
  r_outer[0] = outer(a);
  r_outer[1] = outer(b);
}
