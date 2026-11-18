int g;

void zero(int b) {
  if (b)
    for (;;) {}
}

void test(void) {
  zero(g);
  if (g)
    Frama_C_show_each_g(g);
}
