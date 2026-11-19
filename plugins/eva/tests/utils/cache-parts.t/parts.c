/* Callees whose entries are produced by a first analysis with caching
   disabled, then supplied to a second analysis. Each callee makes no call:
   From and Inout give their parts only for a call that made no call. */

volatile int any;
int a, b = 1, c, d = 2, g, h, out, vin = 3, vout;

/* Two entries with different dependencies: a from b, then c from d. */
void copy(int *dst, int *src)
{
  *dst = *src;
}

/* Narrows its formal. The caller reduces its actual g after the call,
   since the callee does not write g. */
void narrow(int x)
{
  if (x < 0) while (1);
  out = x;
}

/* Narrows its formal and writes its actual h: the caller does not reduce
   h, which is 7 after the call. */
void narrow_and_write(int x)
{
  if (x < 0) while (1);
  h = 7;
}

/*@ assigns vout \from vin; */
void checked(void)
{
  vout = vin;
}

void deps_main(void)
{
  copy(&a, &b);
  copy(&c, &d);
  copy(&a, &b);
}

void inout_main(void)
{
  g = any ? -5 : 5;
  narrow(g);
  h = any ? -5 : 5;
  narrow_and_write(h);
}

int main(void)
{
  deps_main();
  inout_main();
  checked();
  checked();
  return 0;
}
