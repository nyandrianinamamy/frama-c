#include "__fc_builtin.h"
int g, a, out, first, second;
/*@ requires a <= (\let z = g; z); */
void f(void) { out = a; }
int main(void) {
  g = 3; a = Frama_C_interval(0,9); f(); first=out;
  g = 9; out=0; a = Frama_C_interval(0,9); f(); second=out;
}
