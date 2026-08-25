/*@
  requires i>0;
*/
int *f(int i);

/*@
  admit requires i>0;
*/
int *f0(int i);

/*@
  check requires i>0;
*/
int *f1(int i);

/*@
  terminates \true;
*/
int *f2(int i);

/*@
  decreases i;
*/
int *f3(int i);

/*@
  assigns \nothing;
*/
int *f4(int i);

/*@
  allocates \result;
*/
int *f5(int i);

/*@
  ensures i==1;
*/
int *f6(int i);

/*@
  frees i;
*/
int *f7(int *i);

/*@
  requires i>0;
  ensures i==1;
  assigns \nothing;
  allocates \result;
  terminates \true;
  decreases i;
*/
int *f8(int i);

/*@
  requires i>0;
  assigns \nothing;
  decreases i;
  ensures i==1;
  terminates \true;
  allocates \result;
*/
int *f9(int i);

/*@
  behavior B1:
    assumes i==0;
*/
int *f10(int i);

/*@
  behavior B1:
    requires i==0;
*/
int *f11(int i);

/*@
  behavior B1:
    assigns \nothing;
*/
int *f12(int i);

/*@
  behavior B1:
    allocates \result;
*/
int *f13(int i);

/*@
  behavior B1:
    ensures i==0;
*/
int *f14(int i);

/*@
  behavior B1:
    assumes i==0;
    requires i==0;
    ensures i==0;
    allocates \result;
    assigns \nothing;
*/
int *f15(int i);

/*@
  requires i>=0;
  behavior B1:
    assumes i==0;
    requires i==0;
    assigns  \nothing;
    allocates \result;
    ensures i==0;
*/
int *f16(int i);

/*@
  behavior B1:
    ensures i==0;
  disjoint behaviors;
*/
int *f17(int i);

/*@
  behavior B1:
    ensures i==0;
  complete behaviors;
*/
int *f18(int i);
