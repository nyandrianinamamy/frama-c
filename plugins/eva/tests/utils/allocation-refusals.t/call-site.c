/* Loads that combine a cell holding part of a pointer to an allocated block
   with an uninitialized cell, in C and in a requires clause checked at the
   call site. Run with -machdep x86_32: the word covers the pointer and the
   padding. */

#include <stdint.h>
#include <stdlib.h>

union U {
  struct { uintptr_t p; unsigned pad; } s;
  unsigned long long word;
};

unsigned long long result;

void c_word(union U *u) { result = u->word; }

/*@ requires u->word == 0; */
void req_word(union U *u) { result = 1; }

/* The padding is initialized: the combined value designates the block. */
/*@ requires u->word == 0; */
void req_initialized(union U *u) { result = 2; }

/* No pointer in the word. */
/*@ requires u->word == 0; */
void req_plain(union U *u) { result = 3; }

/* The C load of an uninitialized word stops the analysis: it comes last. */
int main(void) {
  union U w, v, plain;
  uintptr_t address = (uintptr_t)malloc(4) ^ 0x1ff;
  w.s.p = address;
  v.s.p = address;
  v.s.pad = 0;
  plain.word = 0;
  req_word(&w);
  req_initialized(&v);
  req_plain(&plain);
  c_word(&w);
  return 0;
}
