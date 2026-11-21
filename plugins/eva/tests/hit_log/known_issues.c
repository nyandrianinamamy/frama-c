/* run.config
   STDOPT: +"-main issue86"
   STDOPT: +"-main issue93_2"
   STDOPT: +"-main issue93_3"
   STDOPT: +"-main issue93_4"
   STDOPT: +"-main issue94_1 -eva-slevel 20 -eva-no-alloc-returns-null"
   STDOPT: +"-main issue94_2 -eva-slevel 20 -eva-no-alloc-returns-null"
   STDOPT: +"-main issue95"
   STDOPT: +"-main issue96"
*/

/* The known issues of #87: memexec reuses a call that a fresh analysis would
   compute differently. The hits are kept, and the answers differ from the
   run without memexec. Each program is that of its issue, with the names
   made unique. */

#include <stdlib.h>
#include "__fc_builtin.h"

int a, g, out, r1, r2;

/* #86: a global read by a precondition. y is reset so that the second call
   is a hit. */
int y;

/*@ requires x >= g; */
int f86(int x) { y = x + 1; P: return y; }

void issue86(int n) {
  int v = n;
  g = 9; y = 0;
  r1 = f86(v);
  v = n;
  g = 4; y = 0;
  r2 = f86(v);
}

/* #93, case 2: an assertion with a part whose dependencies cannot be
   evaluated. */
/*@ predicate opaque(integer x); */
void f93_2(void) { /*@ assert a <= g && opaque(0); */ P: out = a; }

void issue93_2(void) {
  a = Frama_C_interval(0, 9); g = 3; f93_2(); r1 = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; f93_2(); r2 = out;
}

/* #93, case 3: the postcondition of a function analysed by its
   specification. */
/*@ assigns \nothing; ensures a <= g; */ void restrict_a(void);
void f93_3(void) { restrict_a(); P: out = a; }

void issue93_3(void) {
  a = Frama_C_interval(0, 9); g = 3; f93_3(); r1 = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; f93_3(); r2 = out;
}

/* #93, case 4: an assembly statement with an assigns clause. */
int answer;
void f93_4(void) { /*@ assigns g \from \nothing; */ asm(""); P: ; }

void issue93_4(void) {
  g = 4; f93_4();
  g = 9; f93_4();
  answer = g;
}

/* #94, case 1: a pointer comparison after the block became weak. */
extern void Frama_C_show_each_equal(unsigned, int);
int equal_live(const void *pa, const void *pb) { P: return pa == pb; }

int issue94_1(void) {
  void *first = NULL;
  for (unsigned i = 0; i < 2; ++i) {
    void *current = malloc(i + 1);
    if (!current) return 0;
    if (i == 0) first = current;
    int same = equal_live(first, current);
    Frama_C_show_each_equal(i, same);
  }
  return 0;
}

/* #94, case 2: free on a reused call. */
int *owner, *alias;
void release(void) { free(owner); P: owner = NULL; }

int issue94_2(void) {
  for (int i = 0; i < 3; ++i) {
    owner = malloc(sizeof *owner);
    if (!owner) return 0;
    *owner = 17;
    if (i) alias = owner; else alias = NULL;
    release();
  }
  return 0;
}

/* #95: a callee that would be analysed by its specification as a recursive
   call. */
int one, two;
int f95(void);
/*@ assigns \result \from n; ensures 0 <= \result <= 9; */
int h95(int n) { if (n) return f95(); return 2; }
int f95(void) { int v = h95(0); P: return v; }

void issue95(void) {
  one = f95();
  two = h95(1);
}

/* #96: a non-monotone builtin after widening hints were added. */
int xc;
int count96(int n) {
  while (xc < n) ++xc;
  int result = (int)Frama_C_abstract_max(xc);
 P: return result;
}

void discover96(int *p) {
  /*@ loop widen_hints *p, 13; */
  while (*p < 0) ++*p;
}

int issue96(void) {
  xc = 0;
  int first = count96(13);
  discover96(&xc);
  xc = 0;
  int second = count96(13);
  return second;
}
