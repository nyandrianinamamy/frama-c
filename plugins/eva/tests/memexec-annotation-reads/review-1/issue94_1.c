#include <stdlib.h>
extern void Frama_C_show_each_equal(unsigned, int);
static int equal_live(const void *a, const void *b) { return a == b; }
int main(void) {
  void *first = NULL;
  for (unsigned i = 0; i < 2; ++i) {
    void *current = malloc(i + 1);
    if (!current) return 0;
    if (i == 0) first = current;
    int same = equal_live(first, current);
    Frama_C_show_each_equal(i, same);
  }
  return 0;
}
