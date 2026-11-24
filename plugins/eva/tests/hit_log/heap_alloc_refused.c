/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main annot_main"
   STDOPT: +"-eva-no-alloc-returns-null -main mk_main -eva-alloc-builtin fresh"
   STDOPT: +"-eva-no-alloc-returns-null -main mk_main -eva-alloc-builtin imprecise"
   STDOPT: +"-eva-no-alloc-returns-null -main other_main"
   STDOPT: +"-eva-no-alloc-returns-null -main stack_main"
   STDOPT: +"-eva-no-alloc-returns-null -main wrap_main -eva-alloc-functions malloc,calloc,realloc,my_alloc"
*/

/* #127: the calls that allocate that memexec does not store. Each function
   that allocates is called twice, from two call sites, with the same input:
   without -eva-hit-log, memexec stores none of them. With -eva-hit-log, it
   stores the calls that allocate with malloc, calloc, realloc, reallocarray
   (#129) under the policy by_stack, at a statement without annotation
   eva_allocate, on a stack that extends the stored call by one call or
   more. heap_alloc.ml prints the tables of the allocated blocks after each
   analysis, and whether they are those of the run without memexec. */

#include <stdlib.h>
#include <alloca.h>
#include "__fc_builtin.h"

/* Run 0: an annotation eva_allocate at the allocation, with each of the
   policies, by_stack included. */
int *a_fresh(void) {
  /*@ eva_allocate fresh; */
  int *p = malloc(sizeof *p);
  *p = 1;
  return p;
}

int *a_weak(void) {
  /*@ eva_allocate fresh_weak; */
  int *p = malloc(sizeof *p);
  *p = 1;
  return p;
}

int *a_stack(void) {
  /*@ eva_allocate by_stack; */
  int *p = malloc(sizeof *p);
  *p = 1;
  return p;
}

void annot_main(void) {
  int *p1 = a_fresh();
  int *p2 = a_fresh();
  int *q1 = a_weak();
  int *q2 = a_weak();
  int *r1 = a_stack();
  int *r2 = a_stack();
  AN: ;
}

/* Runs 1 and 2: the policies fresh and imprecise, given by option
   -eva-alloc-builtin. */
int *mk(void) {
  int *p = malloc(sizeof *p);
  *p = 1;
  return p;
}

void mk_main(void) {
  int *a = mk();
  int *b = mk();
  MK: ;
}

/* Run 3: calloc, and realloc of a null pointer: stored since #129. */
int *c_alloc(void) {
  int *p = calloc(1, sizeof *p);
  return p;
}

int *r_alloc(void) {
  int *p = realloc((void *)0, sizeof *p);
  *p = 1;
  return p;
}

void other_main(void) {
  int *a = c_alloc();
  int *b = c_alloc();
  int *c = r_alloc();
  int *d = r_alloc();
  OT: ;
}

/* Run 4: a block of alloca, and a variable-length array, both released at
   the end of the call. */
int use_alloca(int n) {
  int *p = alloca(n * sizeof *p);
  *p = n;
  return *p;
}

int use_vla(int n) {
  int a[n];
  a[0] = n;
  return a[0];
}

void stack_main(void) {
  int x = use_alloca(2);
  int y = use_alloca(2);
  int z = use_vla(2);
  int t = use_vla(2);
  ST: ;
}

/* Run 5: an allocation wrapper. With my_alloc in -eva-alloc-functions, the
   policy strips the call of malloc from the stack of the allocation, which
   ends with the call of my_alloc: the creation is not below a call of
   my_alloc, which is not stored. use_alloc calls my_alloc. */
int *my_alloc(void) {
  return malloc(sizeof(int));
}

int *use_alloc(void) {
  int *p = my_alloc();
  *p = 1;
  return p;
}

void wrap_main(void) {
  int *a = use_alloc();
  int *b = use_alloc();
  WR: ;
}
