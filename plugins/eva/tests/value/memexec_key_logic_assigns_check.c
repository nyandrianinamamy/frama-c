/* run.config
   OPT: @EVA_TEST@ -from-verify-assigns
   OPT: @EVA_TEST@ -from-verify-assigns -eva-no-memexec
   OPT: @EVA_TEST@ -from-verify-assigns -main from_case
   OPT: @EVA_TEST@ -from-verify-assigns -main from_case -eva-no-memexec
*/
/* run.config*
   DONTRUN:
*/
/* The body does not read p. The optional From checker nevertheless reads p
   to resolve the contract's assigned location. The first call satisfies the
   clause; the second cannot be proved to satisfy it. Both must be analyzed
   so that the second call's assigns and from diagnostics are retained. */

int x, y, z, *p, answer;

/*@ assigns *p \from \nothing; */
void f(void) { x = 1; }

int main(void) {
  p = &x; x = 0; f();
  p = &y; x = 0; f();
  answer = x;
}

/* Address reads in the from part also decide the result of verification. */
/*@ assigns x \from *p; */
void read_f(void) { x = y; }

void from_case(void) {
  y = 1;
  p = &y; x = 0; read_f();
  p = &z; x = 0; read_f();
  answer = x;
}
