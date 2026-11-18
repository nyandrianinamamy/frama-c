#include <stdint.h>

int g, out;

void temporary_mix(void) {
  if ((uintptr_t)&g / 4u)
    out = 1;
}
