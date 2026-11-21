int g, out, first, second;
/*@ behavior keep:
      assumes g == 0;
      assigns \nothing;
    behavior change:
      assumes g != 0;
      assigns out \from \nothing;
    complete behaviors; disjoint behaviors;
*/
void pick(void);
void f(void) { pick(); }
int tag;
void outer(void) { tag = 7; f(); }
int main(void) {
  g = 1; out = 41; tag = 1; outer(); first = out;
  g = 0; out = 42; f();
  g = 1; out = 42; tag = 2; outer(); second = out;
}
