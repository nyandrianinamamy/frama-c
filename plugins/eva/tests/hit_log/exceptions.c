/* run.config
   MODULE: @PTEST_NAME@
   STDOPT:
*/

/* Exceptions that stop an analysis with -eva-hit-log. exceptions.ml raises
   an exception of its own, which Eva does not clean up after: in a hook run
   before the iteration, in a hook run at the call of leaf, and in a hook run
   at the end of the analysis of the body of leaf, before its cache entry is
   recorded. It then asks for the state at each labelled statement and at the
   start of each function, in the hook run when the analysis is aborted and
   after the exception is caught, and prints whether the requests are
   answered by the rule.
   Expected: after the exception raised before the iteration, the requests
   are not answered by the rule. After the other two, the calls that the
   exception stops are interrupted: those of main, f and leaf. Each statement
   of their bodies is unavailable, never unreachable, including those that
   Eva has visited (M, A and B, and L for the last exception), and the start
   of each function is answered. A last analysis, without exception, answers
   every request. */

int g;

void leaf(void) { L: g = 2; }

void f(void) { A: g = 1; B: leaf(); C: g = 3; }

int main(void) { M: f(); return g; }
