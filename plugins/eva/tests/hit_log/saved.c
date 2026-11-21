/* run.config
   MODULE:
   COMMENT: the command omits @PTEST_FILE@, which the run with -load does not take
   CMD: @frama-c@ @PTEST_OPTIONS@
   EXECNOW: BIN @PTEST_NAME@.sav LOG @PTEST_NAME@_sav.res LOG @PTEST_NAME@_sav.err @frama-c@ -machdep x86_32 -eva-verbose 0 -eva-no-remove-redundant-alarms -eva-hit-log -eva -save @PTEST_NAME@.sav @PTEST_FILE@ > @PTEST_NAME@_sav.res 2> @PTEST_NAME@_sav.err
   MODULE: @PTEST_NAME@
   STDOPT: +"@PTEST_FILE@"
   STDOPT: +"-load %{dep:@PTEST_NAME@.sav}"
*/

/* The recording is kept by a copy of the project, and by a project saved and
   loaded, in the same process (first run) or in another one (second run):
   their requests are answered by the rule, as in the original project or in
   a new analysis. The second call of parent is a hit, and the call of leaf
   is below it: the calls stored in the cache entries are kept as well.
   saved.ml makes the requests. */

#include "__fc_builtin.h"

int c, g, h;

void f(void) { if (c) g = 0; P: g = 1; }

int k;

void leaf(int x) { Q: k = x; }

void parent(void) { leaf(3); }

int main(void) {
  c = Frama_C_interval(0, 1);
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
  g = 9; h = 5; f();
  h = 1; k = 0; parent();
  h = 2; k = 0; parent();
  return 0;
}
