int g;
void f(void) {
  int uninit;
  /*@ assert g == 0 || (\let z = uninit; z == z); */
  return;
}
int main(void) { g=0; f(); }
