/* The callee of logic.c called first with an address among two, then with
   one of them. */

volatile int any;
int a, b, result;

int leaf(int *p, int x)
{
  /*@ assert no_eva: *p >= 0; */
  return x + 1;
}

int main(void)
{
  int *p = any ? &a : &b;
  result = leaf(p, 1);
  result = leaf(&a, 1);
  return result;
}
