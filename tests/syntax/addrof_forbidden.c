/* run.config
   OPT: -cpp-extra-args="-DPACKED"
   EXIT: 1
   OPT: -cpp-extra-args="-DBITFIELD"
   OPT: -cpp-extra-args="-DREGISTER"
   OPT: -cpp-extra-args="-DREGISTER_ARRAY"
*/

int main(void)
{
#ifdef PACKED
  struct mps
  {
    char c;
    int i;
  } __attribute__((__packed__));

  struct mps s;
  &s.i; // warning
#endif
#ifdef BITFIELD
  struct bf
  {
    char b : 1;
  } b;
  &b.b; // rejected
#endif
#ifdef REGISTER
  register int x;
  &x; // rejected
#endif
#ifdef REGISTER_ARRAY
  register int x[3];
  x[0] = 1; // allowed
  &x; // rejected
#endif

}
