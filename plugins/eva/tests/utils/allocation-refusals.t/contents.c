/* Bodies that write a part of a block whose other part holds part of a
   pointer to an allocated block, without reading it. */

#include <stdlib.h>

volatile int nondet;

struct P {
  union { char c[sizeof(int *)]; int *p; } u;
  char d;
} part;

struct Q { char c; int k; } plain;

/* Joins two offsetmaps of part. */
void partial(void) {
  if (nondet)
    part.d = 2;
  else
    part.d = 3;
}

void partial_once(void) { part.d = 4; }

/* The same writes to a block without pointer. */
void control(void) {
  if (nondet)
    plain.c = 2;
  else
    plain.c = 3;
}

/* Reads a field beside a field that holds a pointer to an allocated
   block, without reading the pointer. */
struct S { int n; int *p; } holder;
int seen;

void sibling(void) { seen = holder.n; }

int main(void) {
  int *q = malloc(sizeof *q);
  if (!q)
    return 1;
  part.u.p = q;
  part.u.c[0] = 0;
  partial();
  partial_once();
  control();
  holder.p = q;
  sibling();
  return 0;
}
