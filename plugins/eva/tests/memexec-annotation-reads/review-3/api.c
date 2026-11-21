#include <string.h>
char text[]="ab";
int a[4], answer;
void f(void) {
  /*@ check a[strlen((char *)text)] == 0; */
  answer=1;
}
int main(void) {f();}
