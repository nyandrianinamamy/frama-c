/* run.config
   STDOPT: +"-main issue97_b3_renamed -eva-slevel 10 -eva-no-alloc-returns-null"
   STDOPT: +"-main hints_renamed -eva-slevel 10 -eva-no-alloc-returns-null"
*/

/* Known issues shown by a hit under a renaming (#125). In each run, a
   function is called on two allocated blocks with equal snapshots. Before
   #125, a block of the key was compared by identity: the second call was
   analysed, and the answers were equal to the run without memexec. Since
   #125, the second call is a hit through the renaming of the first block to
   the second, and the answers differ from the run without memexec. These
   are apart from known_issues_97.c: a run there changes the counts of its
   first run. */

#include <stdlib.h>
#include "__fc_builtin.h"

/* #97, case B3, reached through a renaming: a pointer read by \initialized
   is not in the key. The dependencies of the assertion replace the read of
   g97 by the bits of the block it points to. At the first call, g97 points
   to the initialised block a, and the assertion reduces value to 0. At the
   second call, g97 points to the uninitialised block c, which the stored
   call does not mention, and the argument is b. The entry mentions a only,
   and b has the same snapshot, so the second call is a hit through the
   renaming a -> b. It answers 0, where the run without memexec answers 0 or
   1. */
int *g97;

int limit97(int *p, int value) {
  //@ assert \initialized(g97) ==> value == 0;
  return value;
}

int results97[2];
void issue97_b3_renamed(void) {
  int *a = calloc(1, sizeof *a);
  int *b = calloc(1, sizeof *b);
  int *c = malloc(sizeof *c);
  g97 = a;
  results97[0] = limit97(a, Frama_C_interval(0, 1));
  g97 = c;
  results97[1] = limit97(b, Frama_C_interval(0, 1));
}

/* Widening hints given by an annotation are kept for a block, outside the
   state: they are in neither the key nor the snapshot. discover gives the
   block a the hint 13. count(a, 13) widens *a to 13 at most, and ends with
   *a equal to 13. count(b, 13) is a hit through the renaming a -> b and
   answers 13 for *b, where the run without memexec, with no hint on b,
   widens *b beyond 13. This is a limit recorded under the assumption of
   #120 on widening: the key holds the state, not what widening reads
   besides it. */
void discover(int *q) {
  /*@ loop widen_hints *q, 13; */
  while (*q < 0) ++*q;
}

int count(int *p, int n) {
  while (*p < n) ++*p;
  return *p;
}

int x, y;
void hints_renamed(void) {
  int *a = calloc(1, sizeof *a);
  int *b = calloc(1, sizeof *b);
  discover(a);
  x = count(a, 13);
  y = count(b, 13);
}
