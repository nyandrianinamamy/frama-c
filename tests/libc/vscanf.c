#ifndef __FRAMAC__
# include <stdarg.h>
# include <stddef.h>
# include <stdint.h>
# include <stdio.h>
#else
# include "stdio.c"
# include "__fc_builtin.h"
#endif

int caller_stub_for_vscanf(const char * restrict format, ...) {
  va_list args;
  va_start(args, format);
  int res = vscanf(format, args);
  va_end(args);
  return res;
}

int main() {
  int d;
  char c;
  long double Ld;
  char s[30];
  ptrdiff_t t;
  uintmax_t j;
  size_t z;
  wchar_t lc;
  int res = caller_stub_for_vscanf("%d %2c %41Lf %s %ti %jx %zu %lc", &d, &c, &Ld, s, &t, &j, &z, &lc);
#ifdef __FRAMAC__
  if (res >= 1) {
    //@ check \initialized(&d);
  }
  if (res >= 2) {
    //@ check \initialized(&c);
  }
  if (res >= 3) {
    //@ check \initialized(&Ld);
  }
  if (res >= 8) {
    //@ check \initialized(&s);
    Frama_C_show_each_must_be_reachable(d, c, Ld, s, t, j, z, lc);
  }
#else
  printf("res = %d\n", res);
#endif
  return 0;
}
