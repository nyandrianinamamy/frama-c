/* Test of the request for the possible values of lvalues, expressions and
   predicates. See test_request.ml for details. */

volatile unsigned int nondet;

struct S {
  char c1;
  char c2;
  int array[10];
};

void unreachable(void);

/* Tests request for the possible values of several variables, lvalues,
   expressions and predicates at the return statement. */
void values (void) {
  /* Integer values. */
  int one = 1;
  int i_set = (nondet % 6) * 5;
  int i_itv = (nondet % 120);
  int i_itv_modulo = (nondet % 50) * 3 + 1;

  /* Offsetmaps for array. */
  int a[10], b[10];
  //@ loop unroll 6;
  for (int i = 0; i < 10; i++) {
    a[i] = i;
  }
  for (int i = 0; i < 10; i++) {
    b[i] = i;
  }

  /* Offsetmaps for struct. */
  struct S st;
  st.c1 = 42;
  st.c2 = i_itv;
  for (int i = 0; i < 10; i++) {
    st.array[i] = i;
  }

  /* Uninitialized variable. */
  int uninit;

  /* Pointer values. */
  int *ptr = 0;
  if (nondet) ptr = &uninit;
  if (nondet) ptr = &st.array[6];
  if (nondet) ptr = &a[nondet % 10];
}

/* Tests request for the possible values of local variable [x]
   at each statement. */
void values_by_stmt () {
  int x = nondet % 100;
  x++;
  if (x < 10)
    x = 10;
  if (x < 0)
    unreachable();
  /*@ assert x > 20; */
}

/* Tests request for the possible values of local variable [x]
   in each callstack. */
void values_by_callstack (int i) {
  int x = 2 * i;
}

void caller (void) {
  values_by_callstack(1);
  int set = (nondet % 5);
  values_by_callstack(set);
  int itv = (nondet % 100);
  values_by_callstack(itv);
}

void main (void) {
  values();
  values_by_stmt();
  caller();
}
