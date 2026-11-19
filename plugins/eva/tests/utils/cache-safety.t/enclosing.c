/* The Safety part of parent, which calls child: child is analysed in a
   first analysis, then answered by a hit in a second one. */

int x, out;

void child(void) {
  /*@ check big: x > 100; */
  out = x;
}

void parent(void) {
  child();
}

int main(void) {
  x = 1;
  parent();
  return out;
}
