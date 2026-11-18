/* run.config
   COMMENT: One analysis prints the dispositions of each call under the message
   COMMENT: category "cache" and writes the statistics, whose memexec rows are
   COMMENT: kept in a second log.
   EXECNOW: LOG @PTEST_NAME@.cache.log LOG @PTEST_NAME@.err.log LOG @PTEST_NAME@.stats.log BIN @PTEST_NAME@.csv @frama-c@ @PTEST_FILE@ -eva @EVA_OPTIONS@ -eva-msg-key cache -eva-statistics-file @PTEST_NAME@.csv > @PTEST_NAME@.cache.log 2> @PTEST_NAME@.err.log && grep '^memexec-' @PTEST_NAME@.csv > @PTEST_NAME@.stats.log
   NOFRAMAC: the analysis is run by the EXECNOW directive.
*/
/* run.config*
   DONTRUN: the dispositions depend on the domains; this test uses the default.
*/

/* Dispositions of the calls through the call-cache seam, with memexec:
   - the first call to [leaf] finds no candidate, is analysed and stored;
   - the second call to [leaf] hits the entry stored by the first one, and
     its body is not analysed: [leaf] prints its argument only once;
   - the call to [alloc] finds no candidate and is analysed; its storage is
     refused because it creates a new allocated block, and so is the storage
     of [main]. */

#include <stdlib.h>

int leaf(int x) {
  Frama_C_show_each_leaf(x);
  return x + 1;
}

int *alloc(void) {
  return malloc(sizeof(int));
}

int main(void) {
  int a = leaf(1);
  int b = leaf(1);
  int *p = alloc();
  return a + b + (p != NULL);
}
