#include "__fc_builtin.h"
int a,g,out,r1,r2;
void leaf(int x){int z=x; /*@ assert a <= g+z; */ out=a;}
void mid(void){leaf(0);}
void (*fp)(void)=mid;
void outer(void){fp();}
void main(void){
a=Frama_C_interval(0,9);g=3;mid();
a=Frama_C_interval(0,9);out=0;outer();r1=out;
a=Frama_C_interval(0,9);out=0;g=9;outer();r2=out;
}
