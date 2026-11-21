int one, two;
int f(void);
/*@ assigns \result \from n; ensures 0 <= \result <= 9; */
int h(int n) { if (n) return f(); return 2; }
int f(void) { int v = h(0); return v; }
int main(void) { one = f(); two = h(1); }
