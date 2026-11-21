#include "__fc_builtin.h"
int k,g,a,out,first,second;
/*@ requires k == 1;
    assigns \nothing;
    behavior selected:
      assumes 1 \in (1 .. k);
      ensures a <= g;
*/
void choose(void);
void f(void) {choose();out=a;}
int main(void){
  k=Frama_C_interval(0,1); a=Frama_C_interval(0,9); g=3; f(); first=out;
  k=Frama_C_interval(0,1); a=Frama_C_interval(0,9); g=9; out=0; f(); second=out;
}
