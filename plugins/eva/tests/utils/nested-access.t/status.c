int x, out;
void g(void) { /*@ assert x != 0; */ out = 11; }
void f(void) {
  x = 0;
  g();
}
int main(void) {
  x = 2;
  f();
  return out;
}
int second(void) {
  x = 9;
  f();
  return out;
}
