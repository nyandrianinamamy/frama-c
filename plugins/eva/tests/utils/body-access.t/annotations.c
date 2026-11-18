#include <stdlib.h>
#include <string.h>

int selector = 1, pre_only = 9, post_only = 7;

/*@ behavior selected:
      assumes selector == 1;
      requires pre_only > 0;
      ensures post_only == 7;
*/
void selected(void) {}

void select_behavior(void) {
  selected();
}

int assertion_only = 1, invariant_only = 2;
int checked = 3;
char text[] = "ab";
char *message = text;

void read_assertion(void) {
  //@ assert assertion_only == 1;
}

void read_invariant(void) {
  //@ loop invariant invariant_only == 2;
  for (int i = 0; i < 2; ++i) {}
}

void read_pointer(void) {
  //@ check \initialized(&checked);
}

void read_string(void) {
  //@ check strlen(message) == 2;
}

int narrowed, other;

void narrowing(void) {
  //@ assert narrowed == 0;
}

int post_input, before_only = 1;

/*@ ensures post_input == \old(before_only) + 1; */
void read_old(void) {
  post_input = 2;
}

/*@ axiomatic Opaque {
      predicate opaque{L}(integer value);
    }
*/

void opaque_assertion(void) {
  //@ check opaque(0);
}

/*@ ensures opaque(0); */
void opaque_contract(void) {}

void allocation_table(void) {
  //@ check \freeable(&checked);
}

int zero_divisor = 0, quotient;

void alarm_assertion(void) {
  quotient = 42 / zero_divisor;
}

int *allocated_ptr;

void valid_pointer(void) {
  //@ check \valid(allocated_ptr);
}

void use_allocated(void) {
  allocated_ptr = malloc(sizeof *allocated_ptr);
  if (allocated_ptr)
    valid_pointer();
}

/* With -machdep x86_32, the word of [all] covers the pointer [s.p] and the
   uninitialized [s.pad]. */
union parts {
  struct { int *p; unsigned pad; } s;
  unsigned long long all;
};

void logic_word(union parts *u) {
  //@ check u->all == 0;
}

void c_word(union parts *u) {
  unsigned long long word = u->all;
}

void logic_or_null(union parts *u) {
  //@ check u->s.p == 0;
}

volatile int nondet;

void use_logic_word(void) {
  union parts u;
  u.s.p = malloc(sizeof(int));
  logic_word(&u);
}

void use_c_word(void) {
  union parts u;
  u.s.p = malloc(sizeof(int));
  c_word(&u);
}

void use_logic_or_null(void) {
  union parts u;
  u.s.p = malloc(sizeof(int));
  logic_or_null(nondet ? &u : (union parts *)0);
}

void empty_max(void) {
  //@ check \max(1, 0, \lambda integer i; i) >= 0;
}

void top_freeable(void) {
  //@ check \freeable((void *)(unsigned long)\max(1, 0, \lambda integer i; i));
}

/*@ axiomatic Bound {
      logic integer bound(integer x);
    }
*/

int range[3] = {1, 2, 3};

void let_bottom(void) {
  int uninit;
  //@ assert \let v = uninit; v == v;
}

void let_function(void) {
  //@ check \let f = \lambda integer x; x; f(1) == 1;
}

void range_bound(void) {
  //@ check \subset(range[0 .. bound(1)], {1, 2, 3});
}

void split_expression(int x) {
  //@ split x != 5;
  quotient = x;
}

void split_predicate(int x) {
  //@ split \initialized(&x) && x != 5;
  quotient = x;
}

int leaf_output;

/*@ assigns \nothing;
    ensures leaf_output == 1; */
void false_leaf(void);

void call_false_leaf(void) {
  false_leaf();
}

int block[3] = {1, 2, 3}, member = 4, *first = block, *second = &member;
float finite = 1;

void memory_builtins(void) {
  /*@ check \separated(first, second)
        && \base_addr(first) == \base_addr(&block[1])
        && \offset(first) == 0 && \block_length(first) > 0
        && \valid_read(first) && \object_pointer(first)
        && \initialized(first) && !\dangling(&second) && \is_finite(finite);
  */
}

void membership(void) {
  //@ check member \in {1, 4};
}

void allocable(void) {
  //@ check \allocable(first);
}

/*@ ensures \fresh{Old, Here}(\result, 4); */
int *fresh(void) {
  return first;
}

int variant_only = 2;

void variant(void) {
  //@ loop variant variant_only - i;
  for (int i = 0; i < 2; ++i) {}
}

/*@ requires depth >= 0;
    decreases depth; */
void decreases_clause(int depth) {}

int global_only = 1;
//@ global invariant positive: global_only >= 0;

struct pair { int left, right; };
//@ type invariant ordered(struct pair p) = p.left <= p.right;
struct pair typed = {1, 2};

void invariants(void) {
  typed.left = 0;
}
