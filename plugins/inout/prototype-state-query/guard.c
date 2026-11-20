/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

#include "__fc_builtin.h"

int g, y;

static void f(int x) {
  if (x <= 4) {
  P:
    y = x;
  }
}

int main(void) {
  int arg = Frama_C_interval(0, 10);
  g = 4;
  y = 0;
  f(arg);
  g = 9;
  y = 0;
  f(arg);
  return g + y;
}
