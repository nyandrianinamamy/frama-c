/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

/* Two calls to f enter with g = 4 and g = 9. P is the point under query.
   The assertion makes Eva evaluate the Init label during the analysis. */

int g, y;

static int f(int x) {
  y = x + 1;
P:
  return y;
}

int main(void) {
  /*@ assert \at(g, Init) == 0; */
  g = 4;
  y = 0;
  f(10);
  g = 9;
  y = 0;
  f(10);
  return g + y;
}
