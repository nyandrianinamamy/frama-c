/* C file for testing Eva abort messages. */

int (*fptr)(int);

int incr (int x) { return x+1; }

/* Without the cvalue domain, Eva cannot evaluate the function pointed to
   by [fptr]. */
void top_function_pointer (void) {
  int (*fptr)(int) = incr;
  int x = (*fptr)(1);
}
