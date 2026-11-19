int x, out;

#if defined(INLINE_SPEC)
/*@ assigns out \from x; */
void child(void);
#else
# if defined(INLINE_BODY)
/*@ requires x == 0; */
# endif
void child(void) {
  /*@ assert x != 0; */
  out = 11;
}
#endif

void f(void) {
  child();
#if defined(INLINE_SPEC)
  /*@ assert x == 0; */
#endif
}

int main(void) {
  f();
  return out;
}
