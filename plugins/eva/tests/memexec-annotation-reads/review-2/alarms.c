#include "__fc_builtin.h"
int g,a,out,table[4];
/*@ requires a <= (g ? 9 : 3); */
void f(void){ out=table[a]; }
int main(void){
 g=0;a=Frama_C_interval(0,9);f();
 g=1;a=Frama_C_interval(0,9);out=0;f();
}
