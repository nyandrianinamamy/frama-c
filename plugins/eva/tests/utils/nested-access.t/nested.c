#include <alloca.h>
#include <stdlib.h>

int x, payload = 7, out, rejected_only;

void outer(void);

/*@ assigns out \from x, payload;
    assigns rejected_only \from x; */
void child(void) {
  if (x == 0)
    out = payload;
  else if (x == 1)
    rejected_only = 42;
#ifdef RECURSIVE_CALLER
  else
    outer();
#endif
}

void outer(void) {
  x = 0;
  child();
}

int main(void) {
  x = 1;
  child();
  outer();
  return 0;
}

int selector = 1, source = 10, destination;

/*@
  requires source >= 0;
  assigns destination \from source;
  behavior enabled:
    assumes selector == 1;
    assigns destination \from source;
    ensures selector == 1;
  behavior disabled:
    assumes selector != 1;
    assigns \nothing;
  complete behaviors;
  disjoint behaviors;
*/
void contract(void);

void spec_parent(void) { contract(); }

int *allocated;
void release(void) { free(allocated); }
void free_parent(void) { release(); }

int free_main(void) {
  allocated = malloc(sizeof *allocated);
  if (allocated)
    free_parent();
  return 0;
}

int *temporary;
void automatic_main(void) {
  temporary = alloca(sizeof *temporary);
  outer();
}

void recursive_main(void) {
  x = 2;
  child();
}

int choice;
void read_x(void) { out = x; }
void maybe_overwrite(void) {
  if (choice)
    x = 0;
  read_x();
}

int formal_in, formal_out;
/*@ assigns formal_out \from local; */
void formal_child(int local);
void formal_parent(void) { formal_child(formal_in); }

int prefix_input = 7, prefix_out, spinning = 1;
void spin(void) {
  prefix_out = prefix_input;
  while (spinning) {}
}
void prefix_parent(void) { spin(); }

/*@ requires payload >= 0; */
void requires_middle(void) { child(); }
void inline_parent(void) {
  x = 0;
  requires_middle();
}

int *sweep_holder;
void own_sweep(void) {
  {
    int local;
    sweep_holder = &local;
  }
}
void sweep_parent(void) { own_sweep(); }
int sweep_main(void) { sweep_parent(); return 0; }

int hint_value;
void hint_reader(void) { while (hint_value < 13) ++hint_value; }
void hint_parent(void) { hint_reader(); }
void hint_marker(void) {}
int hint_main(void) {
  hint_parent();
  hint_marker();
  hint_value = 0;
  hint_parent();
  return hint_value;
}
