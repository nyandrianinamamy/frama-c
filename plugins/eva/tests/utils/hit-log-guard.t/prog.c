/* A program of the tests of Eva, with a header of the share directory. */

#include "__fc_builtin.h"

int g;

int main(void) {
  g = Frama_C_interval(0, 3);
  return g;
}
