/* After the analysis, the refinement of the statuses of alarms and the
   marking of dead code read the states saved for the analysed calls, and a
   hit saves none. */

volatile int v;
int g, out;

/*@ ensures post: out == x + 7; */
void body(int x, int y) {
  if (x == 1 && v) {
    /*@ assert one: x == 1; */
  }
  if (v) out = 100 / y;
  if (x == 3) while (1);
  out = x + g;
}

/* The entry of body(1, 0): one holds, and the division is a sure alarm. */
void producer(void) {
  g = 7;
  body(1, 0);
}

/* The entry of body(2, 1): no alarm. */
void producer_safe(void) {
  g = 7;
  body(2, 1);
}

/* body(2, 1) is analysed, body(1, 0) is a hit. */
int main(void) {
  g = 7;
  body(2, 1);
  out = 0;
  body(1, 0);
  return 0;
}

/* body(1, 0) is analysed, body(2, 1) is a hit. */
int reverse(void) {
  g = 7;
  body(1, 0);
  out = 0;
  body(2, 1);
  return 0;
}

/* body(1, 0) is a hit, and body(3, 1) never returns. */
int no_return(void) {
  g = 7;
  body(1, 0);
  body(3, 1);
  return 0;
}
