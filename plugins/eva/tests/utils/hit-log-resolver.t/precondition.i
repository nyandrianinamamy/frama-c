/* The precondition of f reads z and g, which its body does not read:
   memexec does not compare them. The first call enters with any z and
   g = 9, and its entry survives with z >= 9. The second call has the same
   input but g = 4: with memexec, it reuses the first, while its own entry
   would survive with z >= 4. No entry of the third call survives. */

int g, z, y;

/*@ requires z >= g; */
static int f(int x) {
  y = x + 1;
P:
  return y;
}

int main(int n) {
  y = 0;
  z = n;
  g = 9;
  f(10);
  y = 0;
  z = n;
  g = 4;
  f(10);
  z = 1;
  f(11);
  return y;
}
