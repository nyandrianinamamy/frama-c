/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main scope_main"
   STDOPT: +"-eva-no-alloc-returns-null -main jump_main"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main size_main"
   STDOPT: +"-eva-no-alloc-returns-null -main zero_main"
   STDOPT: +"-eva-no-alloc-returns-null -main negative_main"
   STDOPT: +"-eva-no-alloc-returns-null -main nested_main"
   STDOPT: +"-eva-no-alloc-returns-null -main struct_main"
   STDOPT: +"-eva-no-alloc-returns-null -main alternate_main -eva-slevel 20"
   STDOPT: +"-main scope_main"
   STDOPT: +"-main jump_main"
*/

/* #130: the reuse of a call that makes a variable-length array. The kernel
   allocates the array with __fc_vla_alloc where its declaration is, and
   releases it with __fc_vla_free on each way out of its scope: the end of
   the scope, break, goto and return. The block is owned by the call of the
   function that declares the array; the automatic release at the end of
   that call names it again, already released. A hit replays the creation
   of the block and registers it for the callstack of the hit.
   heap_alloc.ml prints the tables of the allocated blocks after each
   analysis, heap_names.ml the names of the blocks of the policy by_stack,
   and whether those of the analysis with -eva-hit-log are those of the run
   without memexec. */

#include "__fc_builtin.h"

int x;
int *gv;

/* Runs 0 and 9: an array left by the end of its scope. Each function is
   called from two call sites with the same input: the second call is a hit
   on another callstack. escape keeps the address of the array in gv, which
   holds an escaping address after the end of the scope. Run 9 is run 0 with
   the default -eva-alloc-returns-null. */
int scoped(int n) {
  int r;
  {
    int a[n];
    a[0] = n;
    a[n - 1] = 1;
    r = a[0] + a[n - 1];
  }
  return r;
}

void escape(int n) {
  {
    int a[n];
    a[0] = n;
    gv = a;
  }
}

void scope_main(void) {
  x = scoped(2);
  x = scoped(2);
  gv = 0;
  escape(2);
  gv = 0;
  escape(2);
  x = *gv;
}

/* Runs 1 and 10: arrays left by a jump: goto, break, and return from inside
   their scope. Run 10 is run 1 with the default -eva-alloc-returns-null. */
int by_goto(int n) {
  int r = 0;
  {
    int a[n];
    a[0] = n;
    r = a[0];
    if (n > 1) goto out;
    r = 0;
  }
 out:
  return r;
}

int by_break(int n) {
  int r = 0;
  while (1) {
    int a[n];
    a[0] = n;
    r = a[0];
    break;
  }
  return r;
}

int by_return(int n) {
  {
    int a[n];
    a[0] = n;
    return a[0];
  }
}

void jump_main(void) {
  x = by_goto(2);
  x = by_goto(2);
  x = by_break(2);
  x = by_break(2);
  x = by_return(2);
  x = by_return(2);
}

/* Run 2: arrays in a loop, unrolled by slevel. In vloop, the array of each
   iteration is released at the end of the iteration and the policy reuses
   its block at the next one. In grow, the size of the array changes at
   each iteration: the block is reused and resized. The second call of
   each function is a hit on another callstack. */
int vloop(int n) {
  int s = 0;
  for (int i = 0; i < 3; i++) {
    int a[n];
    a[0] = i;
    s += a[0];
  }
  return s;
}

int grow(void) {
  int s = 0;
  for (int i = 1; i < 4; i++) {
    int a[i];
    a[i - 1] = i;
    s += a[i - 1];
  }
  return s;
}

void loop_main(void) {
  x = vloop(2);
  x = vloop(2);
  x = grow();
  x = grow();
}

/* Runs 3 to 5: the size of the array differs between calls: two constant
   sizes, three intervals, zero and a negative size. The assertion of the
   kernel on the bounds of the allocation reduces an interval that holds 0 or
   a negative size to its positive part, in sized and in the argument of its
   caller: the next call has another argument, and the call after it with the
   same argument is a hit. A size of zero or a negative size stops the call,
   which allocates nothing: its second call was a hit before #130 too. */
int sized(int n) {
  int a[n];
  a[0] = n;
  a[n - 1] = 1;
  return a[0] + a[n - 1];
}

void size_main(void) {
  x = sized(2);
  x = sized(2);
  x = sized(3);
  x = sized(3);
  int k = Frama_C_interval(1, 4);
  x = sized(k);
  x = sized(k);
  k = Frama_C_interval(0, 2);
  x = sized(k);
  x = sized(k);
  k = Frama_C_interval(-1, 2);
  x = sized(k);
  x = sized(k);
}

void zero_main(void) {
  if (Frama_C_interval(0, 1)) x = sized(0);
  else x = sized(0);
}

void negative_main(void) {
  if (Frama_C_interval(0, 1)) x = sized(-1);
  else x = sized(-1);
}

/* Run 6: two arrays in nested scopes: the inner one is released first.
   sizeof of an array of variable length is evaluated at its declaration. */
unsigned nested(int n) {
  unsigned r;
  {
    int a[n];
    a[0] = 1;
    {
      int b[n + 1];
      b[n] = a[0];
      r = b[n] + sizeof(b) + sizeof(a);
    }
  }
  return r;
}

void nested_main(void) {
  x = nested(2);
  x = nested(2);
}

/* Run 7: an array of structures. */
struct s { int i; char c; };

int vstruct(int n) {
  struct s t[n];
  t[0].i = n;
  t[n - 1].c = 1;
  return t[0].i + t[n - 1].c + sizeof(t);
}

void struct_main(void) {
  x = vstruct(2);
  x = vstruct(2);
}

/* Run 8: sized called from one call site in a loop, unrolled by slevel,
   with the sizes 2 and 3 in turn. The policy reuses the block of the first
   call at each call, absent, and resizes it: its validity record grows to
   cover both sizes, and its type becomes an array without size. A call
   misses until the record and the type of the block at its start are those
   at the start of an earlier call with the same size: the fifth and sixth
   calls are hits. */
void alternate_main(void) {
  for (int i = 0; i < 6; i++) x = sized(2 + i % 2);
}
