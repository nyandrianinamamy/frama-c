/* run.config
   MODULE: @PTEST_NAME@
   STDOPT: +"-cpp-extra-args=-DHITS=1 -eva-msg-key debug:hit-log"
   STDOPT: +"-cpp-extra-args=-DHITS=100 -eva-msg-key debug:hit-log"
*/

/* The cost of a request without callstack inside a function called below a
   hit. parent is called HITS + 1 times: the first call is analysed and the
   others are hits, which differ from it on h only. The calls of child below
   these hits use the cache entry of the call made by the first call of
   parent. The joined body-entry state of the hits of parent is kept by the
   hit log, so the first request before P in child makes the same number of
   pastes for 1 and for 100 hits; a repeated request makes one paste, the
   other states being memoised. pastes.ml makes the requests, and option
   -eva-msg-key debug:hit-log prints the number of pastes of each. */

int h, out;

void child(void) { P: out = 1; }

void parent(void) { child(); }

int main(void) {
  /*@ loop unroll HITS + 2; */
  for (int i = 0; i <= HITS; i++) { h = i; out = 0; parent(); }
  return 0;
}
