/* run.config
   STDOPT: +"-main disabled -eva-no-results-function nores"
   STDOPT: +"-main recursion -eva-unroll-recursive-calls 4"
   STDOPT: +"-main interrupted -eva-stop-at-nth-alarm 1"
   STDOPT: +"-main disabled -eva-domains cvalue,equality"
*/

/* The closed list of unavailable answers of #87. */

volatile int v;
int g, h, out;

/* Results disabled for a function: the points of its body are unavailable,
   as in the run without recording; its start is answered. */
void nores(void) { P: out = g; }

void disabled(void) {
  g = 1; h = 7; nores();
  g = 1; h = 8; nores();
}

/* Recursive calls unrolled: the points of the body of fact are
   unavailable. */
int fact(int m) { if (m <= 1) return 1; P: return m * fact(m - 1); }

void recursion(void) { out = fact(3); }

/* An analysis interrupted by its first alarm. */
int divide(int d) { P: return 10 / d; }

void interrupted(void) { out = 0; h = 7; out = divide(v); }

/* With another domain than cvalue (last configuration), recording is
   refused. */
