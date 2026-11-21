/* run.config
   MODULE: @PTEST_NAME@
   STDOPT:
   STDOPT: +"-eva-use-spec f"
*/

/* An exception raised by a hook on the results of a call that has no body
   to analyse, with -eva-hit-log. exceptions_results.ml raises an exception
   of its own in the hook run on the results of the second call of f that is
   a hit (first run) or that is analysed by the specification of f (second
   run). It then asks for the state at the start of f and before P, on each
   callstack of f that the hook has seen and without callstack, and before Q
   in other.
   Expected: the call that the exception stops is interrupted, as are the
   calls of main (closed list of #87). The function f is marked whole: P is
   unavailable on every callstack, including that of the first call, whose
   body was analysed to its end, and in the second run, where the run
   without exception answers unreachable. This loss is accepted in #87. The
   start of f and the point Q are answered. */

int g, h;

/*@ assigns g \from \nothing; ensures g == 1; */
void f(void) { P: g = 1; }

void other(void) { Q: h = 1; }

int main(void) {
  other();
  f();
  g = 0; f();
  g = 0; f();
  return g;
}
