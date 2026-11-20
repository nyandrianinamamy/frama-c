/* One function of each analysis status: analyzed with and without saved
   results, analyzed with the specification of its recursive call, used
   through its specification, interpreted by a builtin, and unreachable. */

int r, n, s, e;
char str[4] = "ab";

/*@ assigns \result \from indirect:s[0..]; */
unsigned long strlen(const char *s);

/*@ assigns e \from x; */
void ext(int x);

/*@ assigns r \from k; */
void rec(int k) {
  r = k;
  if (k > 0)
    rec(k - 1);
}

void no_results(void) { n = 1; }

void unreachable(void) { n = 2; }

int main(void) {
  rec(2);
  ext(3);
  s = strlen(str);
  no_results();
  if (s > 10)
    unreachable();
  return 0;
}
