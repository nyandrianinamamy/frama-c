/* run.config
   STDOPT: +"-main issue86"
   STDOPT: +"-main issue93_2"
   STDOPT: +"-main issue93_3"
   STDOPT: +"-main issue93_4"
   STDOPT: +"-main issue94_1 -eva-slevel 20 -eva-no-alloc-returns-null"
   STDOPT: +"-main issue94_2 -eva-slevel 20 -eva-no-alloc-returns-null"
   STDOPT: +"-main issue96"
*/

/* The known issues of known_issues.c, each placed in a callee below a hit:
   the function of the issue is called by a parent function, and the parent
   is called where the program of the issue calls the function. The second
   call of the parent is a hit, and the function of the issue is below it.
   The answers inside it are reported under the issue. */

#include <stdlib.h>
#include "__fc_builtin.h"

int a, g, out, r1, r2;

/* #86: a global read by a precondition. y is reset so that the second call
   is a hit. */
int y;

/*@ requires x >= g; */
int f86(int x) { y = x + 1; P: return y; }

int p86(int x) { return f86(x); }

void issue86(int n) {
  int v = n;
  g = 9; y = 0;
  r1 = p86(v);
  v = n;
  g = 4; y = 0;
  r2 = p86(v);
}

/* #93, case 2: an assertion with a part whose dependencies cannot be
   evaluated. */
/*@ predicate opaque(integer x); */
void f93_2(void) { /*@ assert a <= g && opaque(0); */ P: out = a; }

void p93_2(void) { f93_2(); }

void issue93_2(void) {
  a = Frama_C_interval(0, 9); g = 3; p93_2(); r1 = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; p93_2(); r2 = out;
}

/* #93, case 3: the postcondition of a function analysed by its
   specification. */
/*@ assigns \nothing; ensures a <= g; */ void restrict_a(void);
void f93_3(void) { restrict_a(); P: out = a; }

void p93_3(void) { f93_3(); }

void issue93_3(void) {
  a = Frama_C_interval(0, 9); g = 3; p93_3(); r1 = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; p93_3(); r2 = out;
}

/* #93, case 4: an assembly statement with an assigns clause. */
int answer;
void f93_4(void) { /*@ assigns g \from \nothing; */ asm(""); P: ; }

void p93_4(void) { f93_4(); }

void issue93_4(void) {
  g = 4; p93_4();
  g = 9; p93_4();
  answer = g;
}

/* #94, case 1: a pointer comparison after the block became weak. */
extern void Frama_C_show_each_equal(unsigned, int);
int equal_live(const void *pa, const void *pb) { P: return pa == pb; }

int p94_1(const void *pa, const void *pb) { return equal_live(pa, pb); }

int issue94_1(void) {
  void *first = NULL;
  for (unsigned i = 0; i < 2; ++i) {
    void *current = malloc(i + 1);
    if (!current) return 0;
    if (i == 0) first = current;
    int same = p94_1(first, current);
    Frama_C_show_each_equal(i, same);
  }
  return 0;
}

/* #94, case 2: free on a reused call. */
int *owner, *alias;
void release(void) { free(owner); P: owner = NULL; }

void p94_2(void) { release(); }

int issue94_2(void) {
  for (int i = 0; i < 3; ++i) {
    owner = malloc(sizeof *owner);
    if (!owner) return 0;
    *owner = 17;
    if (i) alias = owner; else alias = NULL;
    p94_2();
  }
  return 0;
}

/* #96: a non-monotone builtin after widening hints were added. */
int xc;
int count96(int n) {
  while (xc < n) ++xc;
  int result = (int)Frama_C_abstract_max(xc);
 P: return result;
}

int p96(int n) { return count96(n); }

void discover96(int *p) {
  /*@ loop widen_hints *p, 13; */
  while (*p < 0) ++*p;
}

int issue96(void) {
  xc = 0;
  int first = p96(13);
  discover96(&xc);
  xc = 0;
  int second = p96(13);
  return second;
}

/* #94, case 1 is no longer a known issue under -eva-hit-log: since #123,
   memexec matches a call with the snapshot of the allocated blocks it
   mentions. The block of first and current is strong at the first call of
   p94_1 and weak at the second one, which is analysed with its call of
   equal_live: no call is below a hit, and every answer of issue94_1 equals
   the run without memexec. */
