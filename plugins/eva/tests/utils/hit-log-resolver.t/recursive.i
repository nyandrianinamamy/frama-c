/* f is recursive: its innermost call uses its specification, and f is
   only partially analyzed. */

int x;

/*@ assigns x, \result \from n; */
int f(int n) {
  if (n <= 0)
    return 0;
  x = n;
  return f(n - 1) + 1;
}

int main(void) {
  return f(2);
}
