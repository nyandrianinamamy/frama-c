/* parent calls child. When a hit answers the call of child in the analysis
   of parent, the writes it delivers are recorded in the Reach part of
   parent, with the call of child as frame. */

int out;

void child(int x) {
  if (x > 0) out = x;
}

void parent(void) {
  child(1);
}

int main(void) {
  parent();
  return 0;
}
