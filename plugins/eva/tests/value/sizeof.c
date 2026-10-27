/* run.config*
   STDOPT: +"-print -machdep gcc_x86_32"
*/

#include <stddef.h>
#include <stdint.h>
#include <limits.h>

volatile unsigned int nondet;
int sz_str,sz_typ,align_str,align_typ;

void main1()
{
  sz_str= sizeof("ONE");
  //@ assert sz_str == sizeof("ONE");
  align_str= __alignof__("FOO");
  // assert align_str == __alignof__("FOO");
  sz_typ= sizeof(char);
  //@ assert sz_typ == sizeof(char);
  align_typ= __alignof__(char*);
  // assert align_typ == __alignof__((char*));
  //@ assert sizeof("BLA") != sizeof("FOOBAR");
  return;
}

struct s {
  int t[10];
};

struct s s1;
volatile int i;

/* Test a not so intelligent bug of Logic_interp, that used to call
   the dependencies of the sizeof() construct present in the alarms. Since
   those have an array type, Value was unhappy. */
void main2() {
  struct s *p = (&s1 + (int)&s1) - (int)&s1; // creates a garbled mix
  p->t[sizeof(s1.t)-i] = 1;
  p->t[sizeof(s1.t)-i] = 2;
}

/* Tests sizeof and alignof on void. Only valid in gcc machdeps. */
void sizeof_void () {
  void *p;
  int size_void = sizeof(void);
  int size_ptr = sizeof(p);
  int size_void_expr = sizeof(*p);
  int align_void = __alignof__(void);
  int align_ptr = __alignof__(p);
  int align_void_expr = __alignof__(*p);
}

void f(int sz) {}

unsigned fsize3(int n) {
  char b[n + 3]; // variable length array
  return sizeof b; // execution time sizeof
}

/* Test the interpretation of sizeof applied to variable length array type,
   where the operand must be evaluated (and possible alarms emitted). */
void sizeof_vla_type(void) {
  int x, y, z;
  size_t size;
  /* Test the values computed for sizeof. */
  x = 42;
  size = sizeof(char[x]);
  Frama_C_show_each_42(size);
  size = sizeof(int[x+8]);
  Frama_C_show_each_200(size);
  x = 3; y = 4; z = 5;
  size = sizeof(short[x][y][z]);
  Frama_C_show_each_120(size);
  x = nondet % 21;
  size = sizeof(int[x]);
  Frama_C_show_each_0_80(size);
  x = nondet % 9; // [0..8]
  y = nondet % 5 + 6; // [6..10]
  z = nondet % 3; // [0..2]
  size = sizeof(short[x+2][y-z][2]);
  Frama_C_show_each_32_400(size);
  /* Test the emission of alarms in the evaluation of sizeof. */
  y = nondet % 10;
  size = sizeof(int[x/y]); // possible division by zero
  x = INT_MAX;
  if (nondet) size = sizeof(int[x+1][2]); // invalid integer overflow alarm
  size_t max = SIZE_MAX;
  if (nondet) size = sizeof(char[max]);
  if (nondet) size = sizeof(int[max]); // overflow: sizeof exceeds SIZE_MAX
}

void main(int *p, int *q, int j) {
  main1();
  main2();
  sizeof_void();
  f(sizeof(*p) * j); // must not crash with equality domain
  int r = fsize3(5);
  sizeof_vla_type();
}
