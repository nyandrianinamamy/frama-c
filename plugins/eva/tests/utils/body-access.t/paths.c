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
