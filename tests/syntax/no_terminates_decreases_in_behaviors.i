/* run.config*
    OPT: -pp-annot -kernel-warn-key=annot-error=warning
 EXIT: 1
   STDOPT:
*/

/*@
  requires i > 0;
  behavior b1:
    requires X == 5;
    ensures X == 3;
    terminates \true;
*/
int *f(int i);

/*@
  requires i > 0;
  behavior b2:
    requires X == 3 + Y;
    requires Y == 2;
    ensures X == Y + 1;
    decreases i;
*/
int *f2(int i);
