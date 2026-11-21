/* run.config
   OPT: @EVA_TEST@ -inout
   OPT: @EVA_TEST@ -inout -eva-no-memexec
*/
/* run.config*
   DONTRUN:
*/
/* Ordinary range evaluation approximates a failed upper bound by infinity.
   The output zone therefore includes a[0..3], even though the dependencies
   are incomplete and must prevent reuse. From must retain this output zone.
   Changing g exercises the failed bound in both call states; a failed
   dependency evaluation must not erase a successfully evaluated location. */

int a[4], g;

/*@ logic integer opaque(integer x); */
/*@ assigns a[0 .. (1 / g + opaque(0))] \from \nothing; */
void range(void);

void range_call(void) { range(); }

int main(void) {
  g = 0;
  range_call();
  a[0] = a[1] = a[2] = a[3] = 0;
  g = 1;
  range_call();
}
