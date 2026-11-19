/*@ assigns \nothing; allocates \nothing; frees \nothing; */ void g(void);
void f(void) { g(); }
int main(void) {
  f();
  return 0;
}
int second(void) {
  f();
  return 0;
}

/*@ assigns \nothing;
    behavior inactive:
      assumes \false;
      assigns \nothing;
      allocates \nothing;
      frees \nothing;
*/
void inactive_contract(void);

void inactive_parent(void) { inactive_contract(); }

int inactive_main(void) {
  inactive_parent();
  return 0;
}
