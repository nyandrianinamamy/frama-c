int first, second, sink;
void body(int x) {
  int *p = &first;
  int i = 0;
  while (i < 2) {
    p = i ? &first : &second;
    sink = *p;
    i++;
  }
}
void producer(void) { body(1); }
int main(void) { body(1); return 0; }
