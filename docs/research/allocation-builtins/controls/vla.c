volatile int n = 3;
int main(void){ int k = n; if (k < 1 || k > 8) return 0; int a[k]; a[0] = 1; return a[0]; }
