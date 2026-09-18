/* run.config*
   STDOPT: #"-eva-domains sign -eva-sign-memory-model simple -eva-msg-key=d-sign"
   STDOPT: #"-eva-domains sign -eva-sign-memory-model cell   -eva-msg-key=d-sign"
*/

/* Tests the sign domain and both memory models Simple_memory and Cell_memory. */

volatile int nondet;
volatile unsigned int pos_nondet;

/* Return any value between [min] and [max] included. */
int range(int min, int max) {
  return pos_nondet % (max - min + 1) + min;
}

/* Tests that the sign domain can prove the absence of division by zero
   in simple cases with scalar integer variables. */
void scalar (void) {
  int x = nondet % 1000;
  int r = 100 / x; // Unknown alarm.
  r = 100 / x; // No alarm if x has been reduced.
  if (x != 0) {
    int r = 100 / x;
  }
  if (x < 0 || x > 0) {
    int r = 100 / x;
  }
  if (x < -10 || x > 42) {
    int r = 100 / x;
  }
  if (x > 1 || x < 1) {
    int tmp = x * 2;
    int r = 100 / tmp;
  }
}

#define SIZE 256

/* Tests that the sign domain can prove the absence of division by zero
   on array cells. */
void array (void) {
  int a[SIZE] = {0};
  int i, r;
  // Fill the array with non-zero values.
  for (i = 0; i < SIZE; i++) {
    int tmp = nondet;
    a[i] = (tmp == 0) ? 1 : tmp;
  }
  r = 100 / a[pos_nondet % SIZE];
  // Fill the array with any values.
  for (i = 0; i < SIZE; i++) {
    a[i] = nondet;
  }
  r = 100 / a[pos_nondet % SIZE]; // Unknown alarm.
  // Divides by an array value if it is not zero.
  i = pos_nondet % SIZE;
  if (a[i] < 0 || a[i] > 0) {
    int r = 100 / a[i];
  }
  // Removes zero values from the array.
  for (i = 0; i < SIZE; i++) {
    if (a[i] == 0) a[i] = 1;
  }
  r = 100 / a[pos_nondet % SIZE];
  // Set one cell to 0.
  a[42] = 0;
  r = 100 / a[43];
  r = 100 / a[range(0, 41)]; // No alarm.
  r = 100 / a[range(10, 42)]; // Unknown alarm
  r = 100 / a[range(42, 100)]; // Unknown alarm
  r = 100 / a[range(41, 43)]; // Unknown alarm
  if (nondet) {
    r = 100 / a[42]; // Sure alarm.
    Frama_C_show_each("UNREACHABLE");
  }
  // Set one cell from the range [100..110] to any value.
  a[range(100, 110)] = nondet;
  r = 100 / a[101]; // Unknown alarm.
  r = 100 / a[111]; // No division by zero.
}

void main (void) {
  scalar();
  array();
}
