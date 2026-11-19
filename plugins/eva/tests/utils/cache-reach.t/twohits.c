int out;
void body(int x) { out = x; }
void producer(void) { body(1); }
int main(void) {
  body(1);
  body(1);
  return 0;
}
