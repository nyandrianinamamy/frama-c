/* With -eva-unroll-recursive-calls 1, the first call to rec analyzes its
   body; the recursive call uses the specification. */

int g;

/*@ assigns g \from n; */
void rec(int n) {
  if (n > 0)
    rec(n - 1);
R:
  g = n;
}

int main(void) {
  rec(2);
  return g;
}
