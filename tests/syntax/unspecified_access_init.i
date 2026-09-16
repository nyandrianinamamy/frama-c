/* run.config
   STDOPT: #"-unspecified-access"
*/

extern void print(const char*, int, int);

void f_noncompliant(int i, int *b) {
  int a = i + b[++i];
  print("%d, %d", a, i);
}

void f_noncompliant_bis(int i, int *b) {
  int a;
  a = i + b[++i];
  print("%d, %d", a, i);
}

void f_compliant(int i, int *b) {
  int a;
  ++i;
  a = i + b[i];
  print("%d, %d", a, i);
}

int main(void) {
  int i = 0;
  int b[] = {40, 41, 42, 43};
  f_compliant(i, b);
  f_noncompliant(i, b);
  f_noncompliant_bis(i, b);
}
