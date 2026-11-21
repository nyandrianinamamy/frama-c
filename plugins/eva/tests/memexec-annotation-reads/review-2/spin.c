#include "__fc_builtin.h"
int c,g;
void f(void) { if(c) g=1; while(1) {} }
int main(void) {
  c=Frama_C_interval(0,1);
  if(Frama_C_interval(0,1)) {g=4;f();} else {g=9;f();}
}
