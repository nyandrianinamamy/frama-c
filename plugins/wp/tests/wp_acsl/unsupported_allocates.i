/*@
  requires \valid(p);
  assigns \nothing;
  frees p;
*/
void f(int *p);

/*@
  requires \valid(p);
  assigns \nothing;
  frees p;
*/
void g(int *p) {
  f(p);
  /*@ assert KO: \valid(p); */
}
