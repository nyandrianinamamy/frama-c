/* The callee of logic.c called twice at one call site, with two different
   addresses. */

int a = 1, b = 2, unused, result;

int leaf(int *p, int x)
{
  /*@ assert no_eva: *p >= 0; */
  return x + 1;
}

int main(void)
{
  int *p = &a;
  for (int i = 0; i < 2; i++) {
    result = leaf(p, 1);
    p = &b;
    unused++;
  }
  return result;
}
