/* run.config
   STDOPT: +"-main issue97_b3 -eva-slevel 10 -eva-no-alloc-returns-null"
*/

/* Known issues of #97, which memexec shows under -eva-hit-log as without
   it: a read made by an annotation is missing from the key. The hits are
   kept, and the answers differ from the run without memexec. These are
   apart from known_issues.c, whose runs analyse the same program: a new
   function there changes the counts of every run. */

#include <stdlib.h>

/* #97, case B3: a pointer read by \initialized is not in the key. It is
   shown here through an assertion, which InOut tracks, rather than through
   the assumes of #97, which it does not. The dependencies of the assertion
   replace the read of gp97 by the bits of the block it points to. gp97
   points to an initialised block at the first call of check97, and to
   another, uninitialised block at the second one. The first block does not
   change, so the second call is a hit, where the assertion is unknown in
   the run without memexec. Both blocks are allocated, but the snapshot of
   #123 does not see the change: the block of the second call is not
   mentioned by the stored call, and gp97 is not in its key. */
int *gp97;

int check97(void) {
  //@ assert \initialized(gp97);
  return 7;
}

int r97[2];
void issue97_b3(void) {
  int *a = calloc(1, sizeof *a);
  int *b = malloc(sizeof *b);
  for (int i = 0; i < 2; i++) {
    gp97 = i ? b : a;
    r97[i] = check97();
  }
}
