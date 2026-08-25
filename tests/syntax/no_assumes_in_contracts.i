/* run.config*
  OPT: -pp-annot -kernel-warn-key=annot-error=warning
 EXIT: 1
   STDOPT:
*/

/*@
  assumes i;
  requires i>0;
*/
int *f(int i);
