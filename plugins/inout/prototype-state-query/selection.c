/**************************************************************************/
/*                                                                        */
/*  SPDX-License-Identifier LGPL-2.1                                      */
/*  Copyright (C)                                                         */
/*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  */
/*                                                                        */
/**************************************************************************/

/* Correlated values on each callstack. On every stack that reaches P,
   x == y and u == w hold; joining the stacks loses both equalities. The
   loop calls g twice from one site: x = y = 3, then 4, and u = w = 3 on
   both visits, so only u == w holds on the joined state of that stack. The
   last call returns before P. s is initialized on the first stack only.
   The block labelled E is never executed: the acceptance driver evaluates
   the expressions of its statements before P. */

int x, y, u, w, r, z;
int a[3];

int f1(int v) { return v; }
int f2(int v) { return v + 1; }

int (*tbl[2])(int) = {f1, f2};

void g(int v, int c) {
  int s;
  x = v;
  y = v;
  u = c;
  w = c;
  if (v == 0)
    return;
  if (v == 1)
    s = 5;
P:
  z = (*tbl[u - w])(v);
E:
  if (c < 0) {
    r = x == y;
    r = u == w;
    r = 100 / (u - w + 1);
    r = a[u - w];
    r = s;
    r = (*tbl[u - w])(v);
  }
}

int main(void) {
  g(1, 1);
  g(2, 2);
  /*@ loop unroll 2; */
  for (int i = 0; i < 2; i++)
    g(3 + i, 3);
  g(0, 0);
  return 0;
}
