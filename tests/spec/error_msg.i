// All annotations below present an error that should be expressed by a
// friendlier msg than the usual unexpected 'bla' token

/*@ requires x >= 0
  ensures \result == 0; */
int f(int x);

/*@ ensures \result >= 0 */
int g(int x);

/*@ assigns \nothing */
int g2(int x);

/*@ allocates \result*/
int g3(int x);

/*@ terminates \true */
int g4(int x);

/*@ decreases x */
int g5(int x);

/*@
  behavior B1:
    assumes i==0
*/
int g6(int x);

/*@
  behavior B1:
    assumes i==0;
  complete behaviors B1
*/
int g6(int x);

/*@
  behavior B1:
    assumes i==0;
  disjoint behaviors B1
*/
int g6(int x);
