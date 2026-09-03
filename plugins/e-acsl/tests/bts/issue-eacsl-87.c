/* run.config
   COMMENT: e-acsl/work_items#87, test for stack overflow with boolean.
*/

#include <stdbool.h>

bool b = false;
bool *foo = &b;

/*@ ensures *foo == false; */
void bar() {}

int main() {

  bar();
  return 0;
}
