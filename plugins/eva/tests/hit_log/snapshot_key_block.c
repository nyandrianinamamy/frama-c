/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main key_block_main"
*/

/* #123: an allocated block of the key that no pointer value of the
   arguments or of the key points to: check_init has no argument, and the
   dependencies of \initialized(gp) replace the read of gp by the bits of
   the block (#97, case B3), so the key holds the block but not gp. Once
   #97 B3 is fixed, gp enters the key and this fixture no longer isolates
   the key blocks. At i = 0, calloc creates a strong block; at i = 1, it
   reuses that block, still live, and makes it weak. The block holds 0 at
   both calls. */

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
