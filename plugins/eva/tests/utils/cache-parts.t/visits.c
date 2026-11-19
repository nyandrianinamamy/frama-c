/* One callee visited from three call sites, each a different branch of the
   callee on the second call. In an analysis with caching disabled, the
   third call is analysed after both branches have been reached; at a hit,
   the third call uses the entry produced by the first call, before the
   second branch was reached. */

int a, b = 1, d = 2;

void choose(int c)
{
  if (c) a = b; else a = d;
}

int main(void)
{
  choose(1);
  choose(0);
  choose(1);
  return 0;
}
