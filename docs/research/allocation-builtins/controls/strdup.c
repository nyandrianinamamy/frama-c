#include <string.h>
int main(void){ char *s = strdup("ab"); return s ? s[0] : 0; }
