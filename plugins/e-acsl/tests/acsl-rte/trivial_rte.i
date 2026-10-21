/* run.config
 * COMMENT: Check that the RTE guards are generated at the right place.
 * STDOPT: #"-e-acsl-rte 3"
*/
/* run.config_dev
 * MACRO: ROOT_EACSL_GCC_FC_EXTRA_EXT -e-acsl-rte 3
*/

int main(void) {

  /*@ assert 4 / 2 == 2; */  // trivial case for division by zero

  int t_1[3] = {1, 2, 3};
  int *ptr_t = t_1;
  /*@ assert t_1[0] == ((int[])ptr_t)[0]; */

  return 0;
}
