#include "__fc_builtin.h"
int a,g,out,r1,r2;
void rec(int n){if(n)rec(n-1);else { /*@ assert a <= g; */ out=a; }}
void f(void){rec(1);}
void main(void){
a=Frama_C_interval(0,9); g=3; f();r1=out;
a=Frama_C_interval(0,9); g=9;out=0; f();r2=out;
}
