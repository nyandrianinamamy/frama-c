volatile int nondet;

void main(void) {
  int array[20], n = 0;

  do {
    Frama_C_show_each(array, n);
    array[n] = nondet % 100;
  }
  while (array[n++] != 0); // True alarm if nondet is never 0
}
