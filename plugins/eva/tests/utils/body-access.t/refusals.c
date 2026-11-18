#include <stdlib.h>

int x, *p, *q;

void copy(void) {
  q = p;
}

/*@ requires x >= 0; */
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
  contract();
  annotation();
  swept();
  p = malloc(sizeof *p);
  if (p)
    nested();
  indirect_caller();
  builtin();
}
