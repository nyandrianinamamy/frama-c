/* run.config
   COMMENT: e-acsl/work_items#87.
*/

int n = 0;

//@ensures *\result==0;
int *new_ptr(void) {
  int *__retres;
  __retres = &n;
  return __retres;
}

int main(int argc, char **argv) {
  new_ptr();
  return 0;
}
