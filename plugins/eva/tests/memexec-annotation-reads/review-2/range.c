#include "__fc_builtin.h"
int buf[5], g,a,out,first,second;
/*@ logic integer opaque(integer x); */
/*@ behavior small: assumes \valid(buf+(0..(opaque(0)+g))); requires a<=3;
    behavior other: assumes !\valid(buf+(0..(opaque(0)+g))); requires a<=9; */
void f(void){out=a;}
int main(void) {
  g=0; a=Frama_C_interval(0,9); f();first=out;
  g=9; out=0; a=Frama_C_interval(0,9); f();second=out;
}
