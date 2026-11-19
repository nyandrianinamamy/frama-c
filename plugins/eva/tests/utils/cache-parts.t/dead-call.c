/* The body of leaf has a call, under a condition that the call of leaf
   does not meet. */

int a, b;

int other(void)
{
  return a;
}

int leaf(int x)
{
  if (x)
    return other();
  return b;
}

int main(void)
{
  return leaf(0);
}
