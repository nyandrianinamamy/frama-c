#include "__fc_builtin.h"
#include <string.h>
char buf[10];
int a,out,first,second;
/*@ ensures out <= \old(strlen(buf)); */
void f(void){out=a;}
int main(void){
 a=Frama_C_interval(0,9); buf[0]=0; f(); first=out;
 a=Frama_C_interval(0,9); buf[0]='x';out=0;f(); second=out;
}
