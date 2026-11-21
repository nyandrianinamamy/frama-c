#include "__fc_builtin.h"
int g;
void spin(void){g=7;while(1){}}
void (*fp)(void)=spin;
void outer(void){fp();}
int main(void){if(Frama_C_interval(0,1)){g=4;outer();}else{g=9;outer();}}
