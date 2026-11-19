/* The body stores the address of its formal into a global. The caller ends
   the lifetime of the formal after the call, and makes the global hold an
   escaping address, after a hit as after an analysis of the body. */

int *gp;
int keep;

void body(int x) {
  gp = &x;
  keep = x;
}

/* The entry of body(1). */
void producer(void) {
  body(1);
}

/* body(2) is analysed; body(1) is a hit. */
int main(void) {
  body(2);
  body(1);
  return 0;
}
