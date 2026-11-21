#include "__fc_builtin.h"
int k, answer;
/*@ requires k == 1;
    ensures narrowed: \old(1 \in (1 .. k)); */
void f(void) { answer=1; }
int main(void) {
  k=Frama_C_interval(0,1);
  /*@ check raw: 1 \in (1 .. k); */
  f();
}
