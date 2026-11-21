/* run.config
   OPT: -eva @EVA_OPTIONS@ -main comprehension_case
   OPT: -eva @EVA_OPTIONS@ -main comprehension_case -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main ordinary_let_case -eva-reduce-on-logic-alarms
   OPT: -eva @EVA_OPTIONS@ -main ordinary_let_case -eva-reduce-on-logic-alarms -eva-no-memexec
*/
/* run.config*
   DONTRUN:
*/

/* Collecting the reads of a comprehension predicate uses Ignore for logic
   alarms. That dependency traversal must not emit a bottom-binding warning.
   The ordinary reduction below explicitly ignores logic alarms and must
   still emit the warning. Both modes preserve the annotation statuses. */

int answer;

void comprehension_f(void) {
  int uninit;
  /*@ check 0 \in { i | integer i;
                   i == 0 || (\let z = uninit; z == z) }; */
  answer = 1;
}

void comprehension_case(void) { comprehension_f(); }

void ordinary_let_f(void) {
  int uninit;
  /*@ assert uninitialized: \let z = uninit; z == z; */
  answer = 1;
}

void ordinary_let_case(void) { ordinary_let_f(); }
