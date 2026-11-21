/* run.config
   MODULE: @PTEST_NAME@
   OPT: @EVA_OPTIONS@
   OPT: @EVA_OPTIONS@ -eva-no-results-domain cvalue
*/
/* run.config*
   DONTRUN:
*/

/* Requests of Eva.Results made in one project while another project is
   analysed, without saved cvalue results, and while the report restarts,
   with the reports of Eva.Legacy_read_trap. legacy_reads_projects.ml makes
   the requests and prints the reports. */

int g;

void f(int x) {
  g = x;
  return;
}

int main(void) {
  f(1);
  f(2);
  return g;
}
