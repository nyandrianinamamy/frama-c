#include "__fc_builtin.h"
int g,h,*p,a,out,first,second;
/*@ behavior small: assumes \separated(p,&h); requires a <= 3;
    behavior big: assumes !\separated(p,&h); requires a <= 9; */
void f(void) { out = a; }
int main(void) {
  p=&g; a=Frama_C_interval(0,9); f(); first=out;
  p=&h; out=0; a=Frama_C_interval(0,9); f(); second=out;
}
