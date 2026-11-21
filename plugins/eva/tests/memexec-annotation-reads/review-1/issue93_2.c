#include "__fc_builtin.h"
/*@ predicate opaque(integer x); */
int a, g, out, r1, r2;
void f(void) { /*@ assert a <= g && opaque(0); */ out = a; }
int main(void) {
  a = Frama_C_interval(0, 9); g = 3; f(); r1 = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; f(); r2 = out;
}
