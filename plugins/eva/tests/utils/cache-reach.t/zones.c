int first, second;
void body(int x) {
  int *p = x == 1 ? &first : &second;
  *p = x;
}
void producer(void) { body(1); }
int main(void) {
  for (int i = 2; i >= 1; i--) body(i);
  return 0;
}
