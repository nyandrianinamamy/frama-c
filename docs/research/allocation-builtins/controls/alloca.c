#include <alloca.h>
int main(void){ int *p = alloca(sizeof(int)); *p = 3; return *p; }
