#include <stdlib.h>

int x, *p, *q, g = 1;

void copy(void) {
  q = p;
}

/*@ requires g > 0; */
void precondition(void) {
  q = p;
}

/*@ ensures x == 1; */
void contract(void) {
  x = 1;
}

void annotation(void) {
  //@ assert x >= 0;
  x = 2;
}

void swept(void) {
  if (x) {
    int local = 3;
    q = &local;
  }
}

void indirect_target(void) {
  x = 4;
}

void nested(void) {
  copy();
}

void (*volatile target)(void) = indirect_target;

void indirect_caller(void) {
  target();
}

void builtin(void) {
  Frama_C_show_each_value(x);
}

void main(void) {
  precondition();
  contract();
  annotation();
  swept();
  p = malloc(sizeof *p);
  if (p)
    nested();
  indirect_caller();
  builtin();
}
