/* run.config
   MODULE: hit_log_observer heap_effects heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main alloca_main"
   STDOPT: +"-eva-no-alloc-returns-null -main vla_main"
*/

/* #130: the heap effects of a call that allocates with alloca or makes a
   variable-length array, and of the automatic release at its end.
   heap_effects.ml prints the effects that each call of a function with a
   body received, when the call ends. The entry of a call ends at the exit
   of its body: the automatic release at the end of the call is received by
   its caller, at the statement of the call, after a hit as after an
   analysed call. heap_alloc.ml and heap_names.ml compare the tables and the
   names of the allocated blocks with those of the run without memexec. */

#include <alloca.h>

int z;
char *gc;

/* Run 0: az makes a block with alloca and keeps its address in gc. The
   second call of az is a hit on another callstack; after each call, gc
   holds an escaping address. z and gc are reset before each call, so that
   the second call has the input of the first. */
void az(void) {
  char *p = alloca(4);
  p[0] = 1;
  z = p[0];
  gc = p;
}

void alloca_main(void) {
  z = 0;
  gc = 0;
  az();
  z = 0;
  gc = 0;
  az();
 Escaping: z = 0;
}

/* Run 1: vz makes a variable-length array, released at the end of its
   scope, and the automatic release at the end of vz names it again. The
   second call of vz is a hit on another callstack. z and gc are reset
   before each call. */
void vz(int n) {
  {
    char a[n];
    a[0] = 1;
    z = a[0];
    gc = a;
  }
}

void vla_main(void) {
  z = 0;
  gc = 0;
  vz(4);
  z = 0;
  gc = 0;
  vz(4);
 Escaping: z = 0;
}
