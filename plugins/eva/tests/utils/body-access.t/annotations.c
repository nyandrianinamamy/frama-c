#include <stdlib.h>
#include <string.h>

int selector = 1, pre_only = 9, post_only = 7;

/*@ behavior selected:
      assumes selector == 1;
      requires pre_only > 0;
      ensures post_only == 7;
*/
void selected(void) {}

void select_behavior(void) {
  selected();
}

int assertion_only = 1, invariant_only = 2;
int checked = 3;
char text[] = "ab";
char *message = text;

void read_assertion(void) {
  //@ assert assertion_only == 1;
}

void read_invariant(void) {
  //@ loop invariant invariant_only == 2;
  for (int i = 0; i < 2; ++i) {}
}

void read_pointer(void) {
  //@ check \initialized(&checked);
}

void read_string(void) {
  //@ check strlen(message) == 2;
}

int narrowed, other;

void narrowing(void) {
  //@ assert narrowed == 0;
}

int post_input, before_only = 1;

/*@ ensures post_input == \old(before_only) + 1; */
void read_old(void) {
  post_input = 2;
}

/*@ axiomatic Opaque {
      predicate opaque{L}(integer value);
    }
*/

void opaque_assertion(void) {
  //@ check opaque(0);
}

/*@ ensures opaque(0); */
void opaque_contract(void) {}

void allocation_table(void) {
  //@ check \freeable(&checked);
}

int divisor = 1;

void alarm_assertion(void) {
  divisor = 42 / divisor;
}

int *allocated_ptr;

void valid_pointer(void) {
  //@ check \valid(allocated_ptr);
}

void use_allocated(void) {
  allocated_ptr = malloc(sizeof *allocated_ptr);
  if (allocated_ptr)
    valid_pointer();
}
