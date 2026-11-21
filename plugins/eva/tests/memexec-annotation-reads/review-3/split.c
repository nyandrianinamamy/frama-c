#include "__fc_builtin.h"
int g, answer;
void f(void) {
  //@ split g;
  answer=1;
}
int main(void) {g=0; f(); answer=0; g=Frama_C_interval(0,1000); f();}
