/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main key_block_main"
*/

/* #123: an allocated block of the key that no pointer value of the
   arguments or of the key points to. check_init has no argument. Its
   assertion reads gp and the block that gp points to, but the key of the
   call holds the block only: the dependencies of \initialized(gp) replace
   the read of gp by the bits of the block (known issue #97, case B3). The
   block is mentioned only because it is in the key. At i = 0, calloc
   creates a strong block; at i = 1, it reuses that block, still live, and
   makes it weak. The block holds 0 at both calls. */

#include <stdlib.h>

int *gp;

int check_init(void) {
  //@ assert \initialized(gp);
  return 7;
}

int r_key_block[2];
void key_block_main(void) {
  for (int i = 0; i < 2; i++) {
    gp = calloc(1, sizeof *gp);
    r_key_block[i] = check_init();
  }
}
