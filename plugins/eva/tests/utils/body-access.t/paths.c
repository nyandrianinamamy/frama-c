volatile int choice;
int q, dead, pair[2], both[2];

void paths(void) {
  if (choice == 0) {
    dead = 1;
    while (1) {}
  }
  if (choice == 1)
    q = 2;
  else
    q = 3;
  pair[0] = 4;
  both[0] = 5;
  both[1] = 6;
}

int g, out, marker;

void guard(void) {
  if (g)
    for (;;) {}
  else
    out = 1;
}

void locals(void) {
  int x;
  out = x;
}

void correlated(int b) {
  if (b)
    dead = 1;
  marker = 1;
  if (b)
    for (;;) {}
}

void alarm(void) {
  out = 10 / g;
}

volatile int *vp;

void volatile_local(void) {
  volatile int x;
  vp = &x;
}

/*@ behavior never:
      assumes g == 42;
      requires g < 0;
*/
void inactive(void) {
  out = 1;
}

void inactive_caller(void) {
  inactive();
}
