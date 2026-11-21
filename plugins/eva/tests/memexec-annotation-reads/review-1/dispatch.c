#include "__fc_builtin.h"
#include <string.h>
int g, cond;
void spin(void) {g=7; while(1){}}
void ret(void) {}
void (*fp)(void);
void indirect(void){fp();}
void fill(void){memset(&g,0,sizeof g);}
void main(void) {
  g=4; fill(); g=9; fill();
  fp=Frama_C_interval(0,1)?spin:ret;
  g=4; indirect(); g=9; indirect();
}
