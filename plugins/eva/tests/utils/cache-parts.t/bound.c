/* A callee with a loop whose bound the loop analysis asks Eva. The names
   are those of the callees whose entries the test module supplies. */

volatile int any;
int a, b = 1, out, bound;

void copy(int *dst, int *src)
{
  for (int i = 0; i < bound; i++)
    out = i;
  *dst = *src;
}

void narrow(int x) { }
void narrow_and_write(int x) { }
void checked(void) { }

int main(void)
{
  bound = any ? 4 : 8;
  copy(&a, &b);
  return a;
}
