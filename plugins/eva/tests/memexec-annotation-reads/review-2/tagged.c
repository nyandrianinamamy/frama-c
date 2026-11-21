#include "__fc_builtin.h"
int g,h,*p,a,out,first,second;
/*@ behavior small: assumes no_eva: g == 0; requires a <= 3;
    behavior big: assumes no_eva: g != 0; requires a <= 9; */
void f(void) { out = a; }
int main(void) {
  g=0; a=Frama_C_interval(0,9); f(); first=out;
  g=1; out=0; a=Frama_C_interval(0,9); f(); second=out;
}
