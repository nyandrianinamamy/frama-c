int budget, first, second;
int f(void) {
  int a[10] = {0};
  //@ loop unroll budget;
  for (int i=0; i<10; i++) a[i] = 42;
  return a[4];
}
int main(void) { budget=12; first=f(); budget=1; second=f(); }
