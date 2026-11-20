/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

int g, y;

static void f(int x) {
  if (x < 0) {
  P:
    y = x;
  }
}

int main(void) {
  g = 4;
  f(2);
  g = 9;
  f(2);
  return g + y;
}
