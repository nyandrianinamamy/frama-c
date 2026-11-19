int x = 9;
void f(void) { Frama_C_dump_each(); }
int main(void) {
  f();
  return x;
}
int second(void) { return 0; }
