/* run.config
   STDOPT: +"-main by_spec -eva-use-spec spec_leaf"
   STDOPT: +"-main by_builtin -eva-builtin builtin_leaf:Frama_C_sqrt"
*/

/* A function called below a hit, and analysed by its specification (first
   run) or by a builtin (second run), is unavailable at every point: at its
   start, and at the points of its body, which the analysis does not reach.
   In each run, the second call of the parent is a hit. The calls are on
   separate lines, so that their callstacks are printed apart. */

int g, h;
double d;

/*@ assigns \nothing; */
void spec_leaf(void) { P: g = 3; }

void spec_parent(void) { spec_leaf(); }

void by_spec(void) {
  spec_parent();
  h = 8;
  spec_parent();
}

/*@ assigns \result \from x; */
double builtin_leaf(double x) { P: g = 3; return x; }

void builtin_parent(void) { d = builtin_leaf(2.0); }

void by_builtin(void) {
  builtin_parent();
  h = 8; d = 0;
  builtin_parent();
}
