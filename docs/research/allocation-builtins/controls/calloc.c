#include <stdlib.h>
int main(void){ int *p = calloc(4, sizeof(int)); return p ? p[0] : 0; }
