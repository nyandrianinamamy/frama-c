void Frama_C_show_each(int, int, int);
volatile int choose;
int x, y, out, *p;
int pick(void) {
  if (p == &x)
    return 1;
  else
    return 2;
}
void g(void) { out = x + y; }
void f(void) {
  *p = pick();
  g();
}
int *getp(void) { return choose ? &x : &y; }
int main(void) {
  p = getp();
  x = 1;
  y = 2;
  f();
  x = 10;
  y = 20;
  f();
  Frama_C_show_each(x, y, out);
  return 100 / (out - 12);
}
