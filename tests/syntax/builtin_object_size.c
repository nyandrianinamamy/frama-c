/* run.config
   STDOPT: +"-machdep=gcc_x86_64"
   STDOPT: +"-machdep=gcc_x86_64" +"-cpp-extra-args=-DWITH_LIBC"
*/

#ifdef WITH_LIBC
#include <features.h>
#endif
int main() {
  struct V { char buf1[10]; int b; char buf2[10]; } var;
  char *p = &var.buf1[1];
  int *q = &var.b;
  return __builtin_object_size(p, 0);
}
