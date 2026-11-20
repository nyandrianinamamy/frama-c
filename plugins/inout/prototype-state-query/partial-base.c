/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

struct pair {
  int a, b;
} s;

static void f(void) {
  s.a = 1;
P:
  s.b = 0;
}

int main(void) {
  s.a = 3;
  s.b = 4;
  f();
  s.a = 8;
  s.b = 9;
  f();
  return s.a + s.b;
}
