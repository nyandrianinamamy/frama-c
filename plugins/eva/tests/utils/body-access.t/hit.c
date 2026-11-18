int p = 7, q;

void copy(void) {
  q = p;
}

int main(void) {
  copy();
  copy();
  return q;
}
