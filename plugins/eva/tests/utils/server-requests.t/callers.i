/* Test of the request about function callers.
   See test_request.ml for details. */

void unreachable (void) {
  return;
}

void one_caller (int i) {
  return;
}

void multiple_callers (int i) {
  return;
}

void multiple_calls (void) {
  multiple_callers(1);
  multiple_callers(2);
}

void main (void) {
  one_caller(0);
  multiple_callers(3);
  multiple_calls();
  return;
}
