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
int main(void) {
  g = 0; out = 42; f(); first = out;
  g = 1; out = 42; f(); second = out;
}
