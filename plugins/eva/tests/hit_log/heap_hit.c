/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main frame_main"
   STDOPT: +"-eva-no-alloc-returns-null -main cond_main"
   STDOPT: +"-eva-no-alloc-returns-null -main cond_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main weak_main"
   STDOPT: +"-eva-no-alloc-returns-null -main two_main"
   STDOPT: +"-eva-no-alloc-returns-null -main chain_main"
   STDOPT: +"-eva-no-alloc-returns-null -main outer_main"
   STDOPT: +"-eva-no-alloc-returns-null -main witness_main -eva-widening-delay 1 -eva-slevel 20 -eva-slevel-function wit_release:0"
   STDOPT: +"-eva-no-alloc-returns-null -main alloca_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main raise_main -eva-widening-delay 1"
   STDOPT: +"-eva-no-alloc-returns-null -main keyed_main"
   STDOPT: +"-eva-no-alloc-returns-null -main single_main"
*/

/* #126: a call whose heap effects are removals and sweeps only is stored by
   memexec and reused. On a hit, the block that the call frees is removed,
   and the pointers to it outside the key of the call, in the frame, are
   swept: replaced by escaping addresses where the call swept the block on
   every path, joined with them where it swept it on some path only. Each
   run is compared by the observer with the run without memexec. In most
   runs, the second call frees another block than the first, of the same
   strength, extent, type and kind: the hit is under a renaming.
   [free] reports the cells that its sweep changes as written: the key of a
   call that frees holds the cells that point to the freed block at its
   start. The pointer to the block is kept in the global cur, which points
   at each call to the block it frees, and the cells of the frame, keep and
   those of bx, point to the block at the second call only. */

#include <stdlib.h>
#include <alloca.h>
#include "__fc_builtin.h"

int *cur, *keep, *keep2;

/* Run 0: a pointer to the freed block in a block of the frame. bx is
   allocated before the calls of rel, which do not read it. At the second
   call, bx->slot and bx->other point to the block freed. */
struct box { int *slot; int *other; };
struct box *bx;

void rel(int *p) { free(p); R: ; }

void frame_main(void) {
  bx = calloc(1, sizeof *bx);
  cur = malloc(sizeof(int));
  *cur = 5;
  rel(cur);
  cur = malloc(sizeof(int));
  *cur = 5;
  bx->slot = cur; bx->other = cur;
  rel(cur);
  M: ;
}

/* Runs 1 and 2: a conditional free. The block is freed on some path only:
   the pointers to it in the frame are joined with escaping addresses. Run 1
   joins the states of the body; run 2 keeps them apart, and the second
   call is made in each state of the first call's exits. */
void cfree(int *p) { if (Frama_C_interval(0, 1)) free(p); C: ; }

void cond_main(void) {
  cur = malloc(sizeof(int));
  *cur = 1;
  cfree(cur);
  cur = malloc(sizeof(int));
  *cur = 1;
  keep = cur;
  cfree(cur);
  N: ;
}

/* Run 3: a weak free. The blocks are weak: the free joins the pointers to
   the block with escaping addresses, and the block stays. */
void wfree(int *p) { free(p); W: ; }

void weak_main(void) {
  /*@ eva_allocate fresh_weak; */
  cur = malloc(sizeof(int));
  wfree(cur);
  /*@ eva_allocate fresh_weak; */
  cur = malloc(sizeof(int));
  keep = cur;
  wfree(cur);
  O: ;
}

/* Run 4: a free with two targets. Both blocks stay, and the pointers to each
   of them are joined with escaping addresses. */
int *g1, *g2;
void tfree(int *p) { free(p); T: ; }

void two_main(void) {
  g1 = malloc(sizeof(int));
  g2 = malloc(sizeof(int));
  if (Frama_C_interval(0, 1)) cur = g1; else cur = g2;
  tfree(cur);
  g1 = malloc(sizeof(int));
  g2 = malloc(sizeof(int));
  keep = g1; keep2 = g2;
  if (Frama_C_interval(0, 1)) cur = g1; else cur = g2;
  tfree(cur);
  Q: ;
}

/* Run 5: a free reached through two intermediate functions. The first call
   of leaf computes its entry. At the second call of top, top and mid are
   analysed, since k differs, and leaf is a hit: top, mid and chain_main
   enclose a hit on the entry of a heap call. */
void leaf(int *p) { free(p); F: ; }
void mid(int *p, int k) { leaf(p); G: ; }
void top(int *p, int k) { mid(p, k); H: ; }

void chain_main(void) {
  cur = malloc(sizeof(int));
  *cur = 3;
  top(cur, 0);
  cur = malloc(sizeof(int));
  *cur = 3;
  keep = cur;
  top(cur, 1);
  S: ;
}

/* Run 6: the same functions, and the second call of top is a hit: the calls
   of mid, leaf and free are below the hit. */
void outer_main(void) {
  cur = malloc(sizeof(int));
  *cur = 3;
  top(cur, 0);
  cur = malloc(sizeof(int));
  *cur = 3;
  keep = cur;
  top(cur, 0);
  U: ;
}

/* Run 7: the witness of the assumption of #120 on widening, with the
   functions renamed. With a hit on the call of wit_release in the second
   iteration, the second assertion would be valid where the run without
   memexec leaves it unknown: the widening in wit_release raises the
   validity record of the block of box, which the frame of the call holds. */
void wit_release(int *p) { while (Frama_C_interval(0, 1)) free(p); free(p); }

int witness_main(void) {
  /*@ eva_allocate fresh_weak; */
  int **box = calloc(1, sizeof *box);
  for (int i = 0; i < 2; ++i) {
    int *p = malloc(sizeof *p); *p = 7;
    if (i) *box = p;
    wit_release(p);
    if (!i) { /*@ assert first: \block_length(box) <= sizeof(int *); */ ; }
    else { /*@ assert second: \block_length(box) <= sizeof(int *); */ ; }
  }
  return 0;
}

/* Run 8: the automatic release at the end of maybe sweeps the block that
   alloca made in an earlier call of maybe on the same callstack, absent from
   the state. The second and third calls of user receive this sweep only.
   No value mentions the block: its sweep cannot be renamed, and memexec does
   not store these calls. */
void maybe(int n) { if (n) { char *s = alloca(4); *s = 1; } }
void user(int n) { maybe(n); V: ; }

void alloca_main(void) {
  for (int i = 0; i < 3; i++) user(i == 0);
  X: ;
}

/* Run 9: a call that frees and whose loop raises the validity record of a
   weak block stays refused. The two calls of wraise have equal input states,
   up to the renaming of the blocks of gp and gq: a hit at the second call
   would leave the record of the block of gp as it was, where the widening
   of the loop raises it, and the assertion would hold. */
int *gp, *gq;
void wraise(int *p, int *q) {
  while (Frama_C_interval(0, 1)) *p = 7;
  free(q);
  Y: ;
}

void raise_main(void) {
  /*@ eva_allocate fresh_weak; */
  gp = malloc(sizeof(int));
  gq = malloc(sizeof(int));
  *gq = 1;
  wraise(gp, gq);
  /*@ eva_allocate fresh_weak; */
  gp = malloc(sizeof(int));
  gq = malloc(sizeof(int));
  *gq = 1;
  wraise(gp, gq);
  /*@ assert raised: \block_length(gp) <= sizeof(int); */
  Z: ;
}

/* Run 10: the freed block is read before it is freed. Both blocks are in
   the key; the second call is a hit, and its block is removed. */
int getrel(int *p) { int v = *p; free(p); K: return v; }

void keyed_main(void) {
  cur = malloc(sizeof(int));
  *cur = 4;
  int ra = getrel(cur);
  cur = malloc(sizeof(int));
  *cur = 4;
  keep = cur;
  int rb = getrel(cur);
  L: ;
}

/* Run 11: a call that frees a block and allocates under the policy
   imprecise, whose single block exists already: the builtin lets memexec
   store the call, and it stays refused. The third call of move has the
   input state of the second. */
int *src, *dst;
void move(void) {
  free(src);
  /*@ eva_allocate imprecise; */
  dst = malloc(sizeof(int));
  E: ;
}

void single_main(void) {
  for (int i = 0; i < 3; i++) {
    src = malloc(sizeof(int)); *src = 2;
    move();
  }
  D: ;
}
