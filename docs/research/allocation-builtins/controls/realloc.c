#include <stdlib.h>
int main(void){ int *p = realloc(0, 2*sizeof(int)); return p != 0; }
