/* run.config
   STDOPT: +"-main hints_on_branch"
   STDOPT: +"-main unroll_bound"
*/

/* Answers more precise than the run without memexec, for the two causes
   admitted by #87. The history of the analysis with memexec differs from
   that of the run without it. */

int x, y, h;

/* Widening hints found on a branch that only a hit makes reachable. The
   second call of count is a hit of a cache entry computed without the hint
   on x, so x > 13 is reachable after it, and hint_y adds a hint on y. The run
   without memexec analyses the second call with the hint on x: x is {13},
   hint_y is not reached, and the loop of loop_y is widened without hint. The
   bounds are variables: a comparison with a constant would be a widening
   hint itself. */
void count(int n) { while (x < n) ++x; }

void discover(int *q) {
  /*@ loop widen_hints *q, 13; */
  while (*q < 0) ++*q;
}

void hint_y(int *q) {
  /*@ loop widen_hints *q, 20; */
  while (*q < 0) ++*q;
 H: ;
}

void loop_y(int n) {
  while (y < n) ++y;
 P: h = 0;
}

void hints_on_branch(void) {
  int bound = 13;
  x = 0; h = 7; count(bound);
  discover(&x);
  x = 0; h = 8; count(bound);
  if (x > bound) hint_y(&y);
  x = 0; y = 0;
  loop_y(20);
}

/* A loop unroll bound read from a global, which is not in the key. The second
   call of unrolled is a hit of the first, analysed with the loop fully
   unrolled. The run without memexec analyses it with one unrolling and
   widens: a[4] is {0; 42}. */
int budget, first, second;

int unrolled(void) {
  int a[10] = {0};
  /*@ loop unroll budget; */
  for (int i = 0; i < 10; i++) a[i] = 42;
 P: return a[4];
}

void unroll_bound(void) {
  budget = 12; first = unrolled();
  budget = 1; second = unrolled();
}
