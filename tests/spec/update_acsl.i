typedef int a;

struct S { int v; int t; int a[5]; } z = { 1, .t=2 };

struct SS { struct S s; int i; } zz;

/*@ logic struct S z2 = {z \with .t = (int) 3 }; */

/*@ logic struct S z3 = {z \with .t = (int) 3, .v = (int) 2 }; */

/*@ logic struct S z4 = {z \with .t = (int) 3, .v = (int) 2 }; */

/*@ logic struct SS zz2 = {zz \with .s = {z \with .t = (int) 3, .v = (int) 2 }, .i = (int) 3 }; */

/*@ logic struct SS zz3 = {zz \with .s = {z \with .t = (int) 3, .v = (int) 2 }, .i = (int) 3 }; */

/*@ logic struct SS zz4 = {zz \with .s = { \with .t = (int) 3, .v = (int) 2 }, .i = (int) 3 }; */

/*@ logic struct SS zz5 = {zz \with .s = { \with .t = (int) 3, .v = (int) 2, .a[4] = (int) 5 }, .i = (int) 3 }; */

/*@ logic struct S z5 = {z \with .t = (int) 3, .a[2+2] = (int) 4 }; */

/*@ logic struct S z6 = {z \with .t = (int) 3, .a = {z.a \with [1] = (int) 1, [2] = (int) 3 } }; */

/*@ logic struct S z7 = {z \with .t = (int) 3, .a = { \with [1] = (int) 1, [2+1] = (int) 3 } }; */
