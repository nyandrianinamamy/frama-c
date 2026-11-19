/* Each call of outer makes a call: From and Inout give no part for it, and
   the entries of outer lack both. The function unused is never called. */

int x = 1, y, z;

void inner(void)
{
  y = x;
}

void outer(void)
{
  inner();
  z = y;
}

void unused(void)
{
  z = 0;
}

int main(void)
{
  outer();
  outer();
  return 0;
}
