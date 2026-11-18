/* String scans of requires clauses, checked at the call site, over a block
   that holds part of the address of an allocated block or an unknown
   value. */

#include <stdint.h>
#include <stdlib.h>

/*@ assigns \result \from \nothing; */
extern void *Frama_C_unknown_target(void);

union S { char bytes[sizeof(void *)]; uintptr_t bits; void *p; };

union S half, unknown;
int x;

/*@ requires valid_read_string(&half.bytes[0]); */
void scan(void) { x = 1; }

/*@ requires strlen(&half.bytes[0]) >= 0; */
void length(void) { x = 2; }

/*@ requires valid_read_string(&unknown.bytes[0]); */
void scan_unknown(void) { x = 3; }

/*@ requires \initialized(&unknown.p); */
void initialized_unknown(void) { x = 4; }

int main(void) {
  scan();
  half.bits = ((uintptr_t)malloc(8)) / 2;
  scan();
  length();
  unknown.p = Frama_C_unknown_target();
  scan_unknown();
  initialized_unknown();
  return 0;
}
