/* run.config
   STDOPT: +"-eva-no-results-domain cvalue"
   STDOPT: +"-eva-no-results"
*/

/* When the states of the cvalue domain are not saved, every state request
   is unavailable, as in the run without recording. There is no hit: without
   these states, the footprints given by InOut are unknown. */

int g, h;

void f(void) { P: g = 1; }

int main(void) {
  h = 1;
  f();
  h = 2;
  f();
  return 0;
}
