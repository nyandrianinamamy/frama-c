#include <stdint.h>

void land_u8(uint8_t x)
{
  uint8_t y;
  y = (uint8_t)(-1) & x;
  /*@ assert y == x; */
  y = x & (uint8_t)(-1);
  /*@ assert y == x; */
}

void land_u16(uint16_t x) {
  uint16_t y;
  y = (uint16_t)(-1) & x;
  /*@ assert y == x; */
  y = x & (uint16_t)(-1);
  /*@ assert y == x; */
}

void land_u32(uint32_t x) {
  uint32_t y;
  y = (uint32_t)(-1) & x;
  /*@ assert y == x; */
  y = x & (uint32_t)(-1);
  /*@ assert y == x; */
}

void land_u64(uint64_t x) {
  uint64_t y;
  y = (uint64_t)(-1) & x;
  /*@ assert y == x; */
  y = x & (uint64_t)(-1);
  /*@ assert y == x; */
}
