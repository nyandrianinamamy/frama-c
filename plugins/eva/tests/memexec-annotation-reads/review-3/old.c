#include "__fc_builtin.h"
int k, a, g, first, second;
/*@ requires k == 1;
    ensures a <= (\old(1 \in (1 .. k)) ? g : 9); */
void f(void) {}
int main(void) {
  k = Frama_C_interval(0,1); a = Frama_C_interval(0,9); g = 3; f(); first = a;
  k = Frama_C_interval(0,1); a = Frama_C_interval(0,9); g = 9; f(); second = a;
}
