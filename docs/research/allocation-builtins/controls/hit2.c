#include <stdlib.h>
int *p; int x;
void h(void){ p = malloc(sizeof(int)); }
void w(void){ h(); }
int main(void){ for (int i = 0; i < 5; i++) w(); return 0; }
