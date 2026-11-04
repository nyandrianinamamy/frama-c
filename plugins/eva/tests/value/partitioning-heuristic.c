/* run.config*

   STDOPT: +"-eva-partition-path 3 -then -eva-partition-path 0 -eva-auto-partition-path 3 -eva-auto-partition-path-include-guards -eva-auto-partition-path-required-writes 1"
   STDOPT: +"-main main_interproc -eva-partition-path 3 -eva-interprocedural-partition-path -then -eva-partition-path 0 -eva-auto-partition-path 3 -eva-auto-partition-path-include-guards -eva-auto-partition-path-required-writes 1"
   STDOPT: +"-main main_enhanced -eva-partition-path 3 -then -eva-partition-path 0 -eva-auto-partition-path 3"
*/

#include "__fc_builtin.h"

void something(int i)
{ (void)i; }

void simple(void)
{
    int i = 0;
    int j;
    if (Frama_C_interval(0, 1) == 1) {
        i = 1;
    }
    Frama_C_show_each(i, j);

    i = 2;
    if (Frama_C_interval(0, 1) == 1) {
        i = 3;
    }
    Frama_C_show_each(i, j);
    j = -i;
    Frama_C_show_each(i, j);
    if (j == -2) {
        something(j);
    }
    Frama_C_show_each(i, j);

    i = 4;
    if (Frama_C_interval(0, 1) == 1) {
        i = 5;
    }
    Frama_C_show_each(i, j);
    ++i;
    Frama_C_show_each(i, j);
    if (i == 6) {
        something(i);
    }
    Frama_C_show_each(i, j);
}

void pointers_f1(void)
{
    int i, j;
    int *p = &i;

    *p = 0;
    if (Frama_C_interval(0, 1) == 1) {
        *p = 1;
    }
    Frama_C_show_each(i);
    j = i;
    Frama_C_show_each(i);

    i = 2;
    if (Frama_C_interval(0, 1) == 1) {
        i = 3;
    }
    Frama_C_show_each(i);
    j = *p;
    Frama_C_show_each(i);
}

void pointers_f2(int *px)
{
    int i;
    int *pi = &i;
    if (Frama_C_interval(0, 1) == 1) {
        *px = 1;
    } else {
        *px = 2;
    }
    Frama_C_show_each(i, *px);
    if (Frama_C_interval(0, 1) == 1) {
        *pi = 3;
    } else {
        *pi = 4;
    }
    Frama_C_show_each(i, *px);
    if (*px == 1) {
        i = 0;
    }
    Frama_C_show_each(i, *px);
}

int **pglob;
int ***allocp(void)
{ return &pglob; }

int pointers_get(int ***p)
{ return ***p; }

void pointers_f3(void)
{
    int i = 1;
    int *p1 = &i;
    int ***p2 = allocp();
    *p2 = &p1;
    if (Frama_C_interval(0, 1) == 1) {
        i = 2;
    }
    Frama_C_show_each(i);
    int j = pointers_get(p2);
    Frama_C_show_each(i);
    int k = j + 1;
    Frama_C_show_each(i);
    *p2 = NULL;
}

void pointers(void)
{
    pointers_f1();

    int x;
    pointers_f2(&x);

    pointers_f3();
}

void loop(void)
{
    int i = 0;
    while (i < 10) {
        something(i);
        if (Frama_C_interval(0, 1) == 1) {
            ++i;
        }
        Frama_C_show_each(i);
    }
    Frama_C_show_each(i);
}

void main(void)
{
    simple();
    pointers();
    loop();
}

int interproc_f1(void)
{
    int x = Frama_C_interval(1, 200);
    if (x >= 101) {
        x -= 201;
    }
    return x;
}

void interproc_f2(int *x)
{
    *x = Frama_C_interval(1, 200);
    if (*x >= 101) {
        *x -= 201;
    }
}

void main_interproc(void)
{
    int x1 = interproc_f1();
    Frama_C_show_each(x1);
    int x2 = interproc_f1();
    Frama_C_show_each(x2);
    x1 = x2;
    Frama_C_show_each(x1, x2);

    int x3;
    interproc_f2(&x3);
    Frama_C_show_each(x3);
    x1 = x3;
    Frama_C_show_each(x3);
}

void enhanced_f(int *x)
{
    int i = Frama_C_interval(-99, 99);
    int j = Frama_C_interval(0, 99);
    Frama_C_show_each(i, j, *x);
    if (i >= 0 && j == 0) return;
    Frama_C_show_each(i, j, *x);
    something(j);
    if (i >= 0) {
        *x = i % j;
    } else {
        *x = -i;
    }
    Frama_C_show_each(i, j, *x);
}

int main_enhanced(void)
{
    int x = 0;
    enhanced_f(&x);
    return x;
}
