#include "__fc_builtin.h"
#include <stddef.h>
int k, t, *p, first, second;
char buffer;
/*@ logic int **opaque(integer x); */
/*@ requires k == 1;
    assigns *((1 \in (1 .. k)) ? &p : (int **)0) \from &t;
    assigns \result \from dest;
    ensures p == &t;
    ensures *p <= 3; */
void *choose(void *dest, const void *src, size_t n);
void f(void) { choose(&buffer, &buffer, 0); }
int main(void) {
  k=Frama_C_interval(0,1); p=0; t=Frama_C_interval(0,3); f(); first=t;
  k=Frama_C_interval(0,1); p=0; t=Frama_C_interval(4,9); f(); second=t;
}
