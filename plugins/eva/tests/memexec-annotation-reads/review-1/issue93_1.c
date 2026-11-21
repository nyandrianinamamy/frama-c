#include "__fc_builtin.h"
int a, g, out, r1, r2;
void leaf(void) { /*@ assert a <= g; */ out = a; }
void f(void) { leaf(); }
int main(void) {
  a = Frama_C_interval(0, 9); g = 3; f(); r1 = out;
  a = Frama_C_interval(0, 9); out = 0; g = 9; f(); r2 = out;
}
