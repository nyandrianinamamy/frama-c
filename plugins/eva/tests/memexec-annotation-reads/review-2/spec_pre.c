#include "__fc_builtin.h"
int k, t, *p, first, second;
/*@ logic int **opaque(integer x); */
/*@ requires k == 0;
    assigns *(k == 0 ? &p : opaque(0)) \from &t;
    ensures p == &t;
    ensures *p <= 3; */
void choose(void);
void f(void) { choose(); }
int main(void) {
  k=Frama_C_interval(0,1); p=0; t=Frama_C_interval(0,3); f(); first=t;
  k=Frama_C_interval(0,1); p=0; t=Frama_C_interval(0,9); f(); second=t;
}
