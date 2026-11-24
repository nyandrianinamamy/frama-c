/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main annot_main"
   STDOPT: +"-eva-no-alloc-returns-null -main plain_main -eva-alloc-builtin fresh"
   STDOPT: +"-eva-no-alloc-returns-null -main plain_main -eva-alloc-builtin fresh_weak"
   STDOPT: +"-eva-no-alloc-returns-null -main plain_main -eva-alloc-builtin imprecise"
*/

/* #129: the calls that allocate with calloc, realloc or reallocarray that
   memexec does not store: at a site with an annotation eva_allocate, with
   any policy, and under another policy than by_stack. Each function that
   allocates is called twice, from two call sites, with the same input, the
   block of g aside, whose content is the same. Each run is compared by the
   observer with the run without memexec; heap_alloc.ml prints the tables
   of the allocated blocks after each analysis, and whether those of the
   analysis with -eva-hit-log are those of the run without memexec. */

#include <stdlib.h>

char *g;

/* Points g to a new block of 4 bytes, filled. */
void mk(void) {
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
}

/* Run 0: an annotation eva_allocate at the allocation, with the policy
   by_stack, which applies without annotation, and with the policy fresh. */
char *c_annot(void) {
  /*@ eva_allocate by_stack; */
  char *p = calloc(4, 1);
  return p;
}

char *r_annot(void) {
  /*@ eva_allocate by_stack; */
  char *p = realloc(g, 8);
  return p;
}

char *ra_annot(void) {
  /*@ eva_allocate fresh; */
  char *p = reallocarray(g, 4, 2);
  return p;
}

void annot_main(void) {
  char *a = c_annot();
  char *b = c_annot();
  mk();
  char *c = r_annot();
  mk();
  char *d = r_annot();
  mk();
  char *e = ra_annot();
  mk();
  char *f = ra_annot();
}

/* Runs 1 to 3: no annotation, with the policy of -eva-alloc-builtin: fresh,
   fresh_weak and imprecise. */
char *c_plain(void) {
  return calloc(4, 1);
}

char *r_plain(void) {
  return realloc(g, 8);
}

char *ra_plain(void) {
  return reallocarray(g, 4, 2);
}

void plain_main(void) {
  char *a = c_plain();
  char *b = c_plain();
  mk();
  char *c = r_plain();
  mk();
  char *d = r_plain();
  mk();
  char *e = ra_plain();
  mk();
  char *f = ra_plain();
}
