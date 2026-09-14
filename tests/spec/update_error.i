/* run.config*
  OPT: -pp-annot -kernel-warn-key=annot-error=warning
 EXIT: 0
   STDOPT:
*/

typedef int a;

struct S { int v; int t; int a[5]; } z = { 1, .t=2 };

struct SS { struct S s; int i; struct S a[5];} zz;

/* No . between .a[4] and a[..].*/
/*@ logic struct S z1 = {z \with .a[4]a[..] = (int) 1} ; */

/* Dotted element before ;.*/
/*@ logic struct S z2 = {z \with .a[4] = (int) 1; .t = (int) 2} ; */

/* Dotted element after ;.*/
/*@ logic struct S z3 = {z \with v = (int) 1; .t = (int) 2} ; */

/* Undotted element before ,.*/
/*@ logic struct S z4 = {z \with v = (int) 1, t = (int) 2} ; */

/* Undotted element after ,.*/
/*@ logic struct S z5 = {z \with .a[4] = (int) 1, t = (int) 2} ; */

/* Other operator than = before ,.*/
/*@ logic struct S z6 = {z \with .a[4] -> (int) 1, .t = (int) 2} ; */

/* Other operator than = after ,.*/
/*@ logic struct S z7 = {z \with .a[4] = (int) 1, .t <- (int) 2} ; */

/* UpdExt in Update.*/
/*@ logic struct S z8 = {z \with .a = {z.a \with [4] -= (int) 0, [3] = (int) 3}} ; */

/* UpdExt in Update.*/
/*@ logic struct S z9 = {z \with .a = { \with [4] += (int) 0, [3] = (int) 3}} ; */

/* UpdExt in Update.*/
/*@ logic struct SS zz1 = {zz \with .a = {\with [4] = {\with t = (int) 2;},}} ; */
