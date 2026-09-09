/* run.config
 * COMMENT: Check that the RTE guards are generated at the right place.
 * STDOPT: #"-e-acsl-O-trivial-rte"
*/
/* run.config_dev
 * MACRO: ROOT_EACSL_GCC_FC_EXTRA_EXT -e-acsl-O-trivial-rte
*/

struct Abstract;

struct Concrete {
  int x;
};

extern struct Abstract *ptr;

int main() {
  /*@ assert ((struct Concrete*)ptr)->x == 42; */
}
