/* run.config
   MODULE: @PTEST_NAME@
   OPT: @EVA_OPTIONS@
   OPT: @EVA_OPTIONS@ -eva-no-join-results
   OPT: @EVA_OPTIONS@ -eva-stop-at-nth-alarm 1
*/
/* run.config*
   DONTRUN:
*/

/* Requests of Eva.Results made during and after the analysis of this file,
   and the reads of the legacy result store reported for each of them by
   Eva.Legacy_read_trap. legacy_reads.ml makes the requests and prints the
   reports. The states joined over the callstacks are computed at the end of
   the first analysis. In the second one, and in the third one, which stops at
   the alarm on t[v], they are computed at the first request at each point,
   possibly made by Eva itself, and then stored. */

volatile int v;
int g, t[2];

void f(int x) {
  g = x;
  return;
}

int main(void) {
 C1:
  f(1);
 C2:
  f(2);
  if (g > 5)
 D: g = 0;
  t[v] = g;
  return g;
}
