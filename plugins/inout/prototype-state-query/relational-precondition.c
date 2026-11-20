/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

/* Not run by the prototype runners. The body of f reads x, and its
   precondition reads x and g. Memexec compares x but not g: with memexec,
   the second call, with g = 4, reuses the first, with g = 9. */

int g, y, r1, r2;

/*@ requires x >= g; */
static int f(int x) {
  y = x + 1;
P:
  return y;
}

int main(int n) {
  int v = n;
  g = 9;
  r1 = f(v);
  v = n;
  g = 4;
  r2 = f(v);
  return 0;
}
