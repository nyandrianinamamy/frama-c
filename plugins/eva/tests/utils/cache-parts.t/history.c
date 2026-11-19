/* From and Inout ask the results of the analysis for each call of leaf
   while the analysis runs: whether each statement is reachable, and the
   state at the start of the function, which the assertion reads at the
   label Pre. The assertion also reads the initial state of the analysis at
   the label Init. The calls with c zero do not reach the branch, which the
   second call reaches. A hit on the entry of the first call restores, at
   the third call, the results computed before the second call. */

int a = 1, x, y, z;

void leaf(int c)
{
  /*@ assert \at(a, Pre) >= 0 && \at(a, Init) >= 0; */
  if (c) {
    x = a;
    y = 1;
  }
  z = 2;
}

int main(void)
{
  leaf(0);
  leaf(1);
  leaf(0);
  return 0;
}
