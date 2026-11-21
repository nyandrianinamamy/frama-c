#include "__fc_builtin.h"
int *p,a,out,first,second;
/*@ behavior small: assumes \initialized(p); requires a <= 3;
    behavior big: assumes !\initialized(p); requires a <= 9; */
void f(void) { out=a; }
int main(void) {
  int x=1,y;
  p=&x; a=Frama_C_interval(0,9); f();first=out;
  p=&y; out=0; a=Frama_C_interval(0,9); f();second=out;
}
