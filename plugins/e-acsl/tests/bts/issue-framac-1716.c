/* run.config
 * COMMENT: Check that the RTE guards are generated at the right place.
 * STDOPT: #"-e-acsl-rte 3"
*/
/* run.config_dev
 * DONTRUN:
*/

struct Abstract;

struct Concrete {
  int x;
};

extern struct Abstract *ptr;

int main() {
  /*@ assert ((struct Concrete*)ptr)->x == 42; */
}
