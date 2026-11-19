/* body stores its argument, the address of a local of mid, into gp. The
   caller of body adds gp to the holders of mid, and when mid returns, gp
   holds an escaping address. */

int *gp;

void body(int *p) {
  gp = p;
}

void mid(void) {
  int local = 0;
  body(&local);
}

/* The entry of body(&local). */
void producer(void) {
  mid();
}

/* The call of body in mid is a hit. */
int main(void) {
  mid();
  return 0;
}
