#include "__fc_builtin.h"
int g, a, out, first, second;
/*@ requires a <= (g ? 9 : 3); */
void f(void) { out = a; }
int main(void) {
  g = 0; a = Frama_C_interval(0,9); f(); first=out;
  g = 1; out=0; a = Frama_C_interval(0,9); f(); second=out;
}
