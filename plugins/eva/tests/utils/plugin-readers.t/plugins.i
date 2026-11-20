/* Plugin readers of Eva's results. h takes a different branch and calls a
   different leaf on each call; g is called from two sites of main and
   writes t2 on its second call only; leaf_a has two callers. main calls
   ptr1 or ptr2 through a table that also holds ptr3, and calls dead_callee
   in a dead branch; uncalled is never called. never_returns does not
   return, so its postcondition is dead. */

volatile int nondet;
int a, b, r, w, rw, u, s, t1, t2, untouched, d;

void leaf_a(void) { a = 1; }
void leaf_b(void) { b = 2; }

/*@ requires u == 0; */
void dead_callee(void) { u = 3; }

void uncalled(void) { u = 4; }

void ptr1(void) { w = 1; }
void ptr2(void) { w = 2; }
void ptr3(void) { w = 3; }

/*@ ensures \result == 0; */
int never_returns(void) { while (1); }

void h(int c) {
  if (c) leaf_a(); else leaf_b();
}

/*@ requires x > 0; */
int g(int x) {
  rw = rw + x;
  t1 = 1;
  if (x > 1) t2 = 2;
  leaf_a();
  return r + x;
}

int main(void) {
  void (*table[3])(void) = { ptr1, ptr2, ptr3 };
  h(1);
  h(0);
  int y = g(1);
  y += g(2);
  table[nondet & 1]();
  if (y < 0) {
    dead_callee();
    /*@ assert y >= 0; */
  }
  /*@ assert y == 3; */
 s = y;
 L: s = s + 1;
  /*@ assert \at(s, L) + 1 == s; */
  d = nondet;
  y = 100 / d;
  if (nondet) never_returns();
  return y;
}
