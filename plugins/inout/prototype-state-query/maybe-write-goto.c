/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

#include "__fc_builtin.h"

int c, g;

static void f(void) {
  if (c) {
    g = 1;
    goto P;
  }
  goto P;
P:
  g = 0;
}

int main(void) {
  c = Frama_C_interval(0, 1);
  g = 4;
  f();
  g = 9;
  f();
  return g;
}
