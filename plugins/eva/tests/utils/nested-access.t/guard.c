int x, out;
void f(void);
/*@ assigns out \from x; */
void g(void) {
  if (x)
    f();
  else
    out = 7;
}
void mid(void) { g(); }
void f(void) {
  x = 0;
  mid();
}
int main(void) {
  f();
  return out;
}
int second(void) {
  x = 1;
  g();
  return out;
}
