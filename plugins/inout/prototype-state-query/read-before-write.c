/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

int g;

static int f(void) {
  int t = g;
P:
  g = 0;
  return t;
}

int main(void) {
  g = 4;
  int a = f();
  g = 9;
  int b = f();
  return g + a + b;
}
