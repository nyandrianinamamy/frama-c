/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

int g, y;

static int f(int x) {
  y = x + 1;
P:
  return y;
}

int main(void) {
  g = 4;
  y = 0;
  f(10);
  g = 9;
  y = 0;
  f(10);
  return g + y;
}
