/* A callee whose assertion Eva does not evaluate (tag no_eva), and whose
   logic inputs Inout computes. Eva reads x only: the address in p is not
   in the key of an entry of leaf. The callee is called at two sites with
   different addresses, and through wrap. */

int a = 1, b = 2, unused, result;

int leaf(int *p, int x)
{
  /*@ assert no_eva: *p >= 0; */
  return x + 1;
}

int wrap(int *p) { return leaf(p, 1); }

int main(void)
{
  result = leaf(&a, 1);
  unused = 9;
  result = leaf(&b, 1);
  result = wrap(&b);
  return result;
}
