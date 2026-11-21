/* run.config
   STDOPT:
*/

/* A conditional write before a loop that never returns. The write is in the
   matching key: the third call, with another value of g, is analysed. The
   second call, which differs only on h, is a hit. Before the loop, the
   answers on the three callstacks are those of the run without memexec. */

#include "__fc_builtin.h"

volatile int v;
int c, g, h;

void f(void) {
  if (c) g = 1;
 L: while (1) {}
}

int main(void) {
  c = Frama_C_interval(0, 1);
  switch (v) {
  case 0: g = 4; h = 7; f(); break;
  case 1: g = 4; h = 8; f(); break;
  default: g = 9; h = 8; f(); break;
  }
  return 0;
}
