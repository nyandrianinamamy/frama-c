/* run.config*
  OPT: -pp-annot -kernel-warn-key=annot-error=warning
 EXIT: 1
   STDOPT:
*/

/*@
  decreases i;
  decreases i;
*/
int *f(int i);

/*@
  terminates \true;
  terminates \true;
*/
int *f2(int i);
