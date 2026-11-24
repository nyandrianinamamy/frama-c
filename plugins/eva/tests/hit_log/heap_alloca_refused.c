/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main annot_main"
   STDOPT: +"-eva-no-alloc-returns-null -main plain_main -eva-alloc-builtin fresh"
   STDOPT: +"-eva-no-alloc-returns-null -main plain_main -eva-alloc-builtin fresh_weak"
   STDOPT: +"-eva-no-alloc-returns-null -main plain_main -eva-alloc-builtin imprecise"
   STDOPT: +"-eva-no-alloc-returns-null -main widen_main -eva-widening-delay 1"
   STDOPT: +"-eva-no-alloc-returns-null -main wrap_main -eva-alloc-functions malloc,calloc,realloc,alloca,my_alloca"
*/

/* #130: the calls that allocate with alloca or make a variable-length array
   that memexec still does not store: an allocation at a site with an
   annotation eva_allocate (run 0), under another policy than by_stack (runs
   1 to 3), a call whose loop raises the validity record of its block of
   alloca by widening (run 4), and an allocation wrapper of alloca (run 5).
   heap_alloc.ml and heap_names.ml compare the tables and the names of the
   allocated blocks with those of the run without memexec. */

#include <alloca.h>
#include "__fc_builtin.h"

int x;

/* Run 0: alloca at a site annotated with the policy by_stack, which is
   also the policy of the command line. */
int annotated(int n) {
  /*@ eva_allocate by_stack; */
  int *p = alloca(sizeof(int));
  *p = n;
  return *p;
}

void annot_main(void) {
  x = annotated(1);
  x = annotated(1);
}

/* Runs 1 to 3: alloca and a variable-length array under the policies
   fresh, fresh_weak and imprecise. */
int plain(int n) {
  int *p = alloca(sizeof(int));
  *p = n;
  return *p;
}

int vplain(int n) {
  int a[n];
  a[0] = n;
  return a[0];
}

void plain_main(void) {
  x = plain(1);
  x = plain(1);
  x = vplain(2);
  x = vplain(2);
}

/* Run 4: alloca in a loop without slevel. The second iteration reuses the
   block of the first, alive, and makes it weak. The second loop initializes
   the weak block and changes nothing else: its widening, applied at once,
   has no effect on the state and raises the validity record of the
   block. */
int wl(void) {
  int *p = 0;
  for (int i = 0; i < 2; i++) p = alloca(sizeof(int));
  while (Frama_C_interval(0, 1)) *p = 7;
  return 0;
}

void widen_main(void) {
  x = wl();
  x = wl();
}

/* Run 5: my_alloca and alloca are in -eva-alloc-functions: the stack of
   the allocation ends with the call of my_alloca, and the block is owned by
   the call of the function that calls my_alloca. my_alloca, an allocation
   wrapper, is not stored; wuse is. */
void *my_alloca(unsigned n) {
  return alloca(n);
}

int wuse(int n) {
  int *p = my_alloca(sizeof(int));
  *p = n;
  return *p;
}

void wrap_main(void) {
  x = wuse(1);
  x = wuse(1);
}
