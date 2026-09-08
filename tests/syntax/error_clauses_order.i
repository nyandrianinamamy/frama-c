/* run.config*
  OPT: -pp-annot -kernel-warn-key=annot-error=warning
 EXIT: 1
   STDOPT:
*/

/*@
  requires i>0;
  assumes i;
*/
int *f(int i);

/*@
  terminates \true;
  assumes i;
*/
int *f2(int i);

/*@
  assigns \nothing;
  requires i>0;
*/
int *f3(int i);

/*@
  assigns \nothing;
  behavior B1:
    ensures i==1;
    requires i>0;
*/
int *f4(int i);

/*@
  assigns \nothing;
  behavior B1:
    ensures i==1;
    assumes i>0;
*/
int *f5(int i);

/*@
  assigns \nothing;
  behavior B1:
    requires i==1;
    assumes i>0;
*/
int *f6(int i);

/*@
  assigns \nothing;
  complete behaviors;
  behavior B1:
    assumes i>0;
*/
int *f7(int i);

/*@
  assigns \nothing;
  disjoint behaviors;
  behavior B1:
    assumes i>0;
*/
int *f8(int i);

/*@
  assigns \nothing;
  complete behaviors;
*/
int *f7(int i);

/*@
  assigns \nothing;
  disjoint behaviors;
*/
int *f8(int i);

/*@
  assigns \nothing;
  behavior B1:
    assumes i>0;
  complete behaviors;
  assigns \nothing;
*/
int *f9(int i);

/*@
  assigns \nothing;
  behavior B1:
    assumes i>0;
  disjoint behaviors;
  requires true;
*/
int *f10(int i);
