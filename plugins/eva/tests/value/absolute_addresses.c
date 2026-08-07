/* run.config*
   STDOPT: +"-commands-file %{dep:absolute_addresses_options.txt}"
   STDOPT: +"-commands-file %{dep:absolute_addresses_options.txt} -main test_valid_pointer_reduction -eva-ilevel 100 "
   STDOPT: +"-commands-file %{dep:absolute_addresses_options.txt} -main test_valid_pointer_reduction -eva-ilevel 100 -warn-invalid-pointer"
*/

/* Valid absolute addresses specified in absolute_addresses_options.txt */
#define ADDR_CHAR 512
#define ADDR_INTS 1024
#define ADDR_UNALIGNED_INTS 1534
#define ADDR_RANGE 2048
#define ADDR_CONST 3072
#define ADDR_VOLATILE 4096
#define ADDR_CONST_VOLATILE 5120

volatile unsigned int nondet;
int g;

/* Writes 0 on all global variables and absolute memory. */
void write_global_zero (void) {
  g = 0;
  *((char *) ADDR_CHAR) = 0;
  // Should have no effect as this is volatile memory.
  *((volatile int *) ADDR_VOLATILE) = 0;

  int *p = (int *) ADDR_INTS;
  int *q = (int *) ADDR_RANGE;
  //@ loop unroll 4;
  for (int i = 0; i < 4; i++) {
    *(p++) = 0; // False alarm
    *(q++) = 0;
  }

  char *r = (char *) ADDR_UNALIGNED_INTS;
  //@ loop unroll 16;
  for (int i = 0; i < 16; i++) {
    *(r++) = 0; // False alarm
  }

  /* Forbidden writes: invalid memory alarms. */
  if (nondet) *((int *) ADDR_CONST) = 0;
  if (nondet) *((volatile int *) ADDR_CONST_VOLATILE) = 0;
}

/* Tests reducing all integers into the valid pointers to absolute addresses.
   The cvalue domain represents pointers on absolute addresses as integer
   values using intervals on integer sets, according to -eva-ilevel.
   An integer interval cannot precisely represent a pointer that can refer to
   several distinct absolute ranges; in this case, reduction to valid pointers
   is imprecise. If enough -eva-ilevel is used, an integer set can precisely
   represent all possible valid pointers to absolute memory; in this case,
   the reduction is precise. */
void test_valid_pointer_reduction (void) {
  volatile char *char_ptr = (volatile char *) nondet;
  Frama_C_show_each_char_ptr(char_ptr);
  char c = *char_ptr; // Alarm
  // Reduction to all absolute valid ranges.
  Frama_C_show_each_read_char_ptr(char_ptr);
  *char_ptr = 42; // Alarm
  // Remove at least the const range starting at &5120.
  Frama_C_show_each_written_char_ptr(char_ptr);

  *char_ptr = 42; // False alarm.

  volatile int *int_ptr = (volatile int *) nondet;
  // Reduce to aligned pointers.
  Frama_C_show_each_int_ptr(int_ptr);
  int r = *int_ptr; // Alarm
  // Remove at least the char change starting at &512.
  Frama_C_show_each_read_int_ptr(int_ptr);
  *int_ptr = 42; // Alarm
  // Remove at least the const range starting at &5120.
  Frama_C_show_each_write_int_ptr(int_ptr);

  *int_ptr = 42; // False alarm.

  int *ptr = (int *) (nondet % 1500);
  r = *ptr;
  /* [ptr] can only points into the range starting at &1024, so the reduction
     is precise and a new access does not lead to new alarms. */
  Frama_C_show_each_precise(ptr);
  *ptr = 1; // False alarm.
}

/* Tests reduction of pointer according to the pointed value. */
void test_pointer_reduction (void) {
  int *p = (int *) ADDR_INTS;
  int *q = (int *) ADDR_RANGE;
  //@ loop unroll 4;
  for (int i = 0; i < 4; i++) {
    *(p++) = i; // False alarm
    *(q++) = 10+i;
  }
  int *ptr = (int *) (nondet ? ADDR_INTS : ADDR_RANGE);
  ptr += (nondet % 4);
  Frama_C_show_each(ptr, *ptr);
  // False alarms in two next lines
  if (*ptr == 2) Frama_C_show_each_2(ptr, *ptr);
  if (*ptr > 10) Frama_C_show_each_gt_10(ptr, *ptr);
}

/* Tests that out-of-bound access in a range of absolute addresses leads to
   alarms. */
void test_out_of_bound_access (void) {
  short s;
  short *sptr = (short *) ADDR_CHAR;
  if (nondet) {
    char c = *sptr; // Invalid memory access alarm.
    Frama_C_show_each_bottom("Should be unreachable");
  }
  if (nondet) sptr = &s;
  *sptr = 0; // Unknown memory access alarm.
  Frama_C_show_each_c(sptr); // [sptr] can only point to &s.

  int *ptr, i;
  ptr = (int *) ADDR_INTS;
  //@ loop unroll 5;
  for (i = 0; i < 5; i++) {
    *ptr = i; // Last iteration leads to an alarm.
    ptr++;
    if (nondet) break;
  }
  Frama_C_show_each_0_3(i); // Previous write is valid for i from 0 to 3.

  ptr = (int *) ADDR_RANGE;
  //@ loop unroll 5;
  for (i = 0; i < 5; i++) {
    *ptr = i; // Last iteration leads to an alarm.
    ptr++;
    if (nondet) break;
  }
  Frama_C_show_each_0_3(i); // Previous write is valid for i from 0 to 3.

  /* [ptr] is aligned, but spans over two distinct ranges of absolute memory */
  ptr = (int *) (ADDR_UNALIGNED_INTS + 2);
  if (nondet) {
    int i = *ptr; // Invalid memory access alarm.
    Frama_C_show_each_bottom("Should be unreachable");
  }
}

/* Tests that writing on const absolute memory leads to alarms. */
void test_const (void) {
  volatile int *ptr = (int *) ADDR_CONST;
  int res = *ptr;
  Frama_C_show_each_unknown(res);
  if (*ptr == 42) {
    Frama_C_show_each_42(*ptr);
  }
  if (nondet) {
    *ptr = 42; // Invalid memory access alarm.
    Frama_C_show_each_bottom("Should be unreachable");
  }
  if (nondet) ptr = &g;
  if (nondet) ptr = (int *) ADDR_INTS;
  if (nondet) ptr = (int *) ADDR_RANGE;
  if (nondet) ptr = (int *) ADDR_CONST_VOLATILE;
  *ptr = 42; // Unknown memory access alarm.
  /* [ptr] should be reduced by removing ADDR_CONST and ADDR_CONST_VOLATILE,
     and [*ptr] can be precise. */
  Frama_C_show_each(ptr, *ptr);
}

/* Checks that no reduction is performed on the values of volatile absolute
   memory pointed to by [ptr]. */
void check_volatile_reduction (volatile int *ptr) {
  if (*ptr == 0) {
    Frama_C_show_each_unknown(*ptr);
  }
  if (*ptr < 10) {
    Frama_C_show_each_unknown(*ptr);
  }
}

/* Tests reads and writes of pointers to volatile absolute memory. */
void test_volatile (void) {
  int i;
  // Non volatile pointer on volatile memory.
  int *iptr = (int *) ADDR_VOLATILE;
  if (nondet) {
    int i = *iptr; // Warning; could be an invalid alarm.
  }
  if (nondet) iptr = &i;
  if (nondet) {
    *iptr = 42; // Warning; could be an unknown alarm with reduction of [ptr].
  }

  volatile int *ptr = (volatile int *) ADDR_VOLATILE;
  *ptr = 42;
  Frama_C_show_each_unknown(*ptr);

  check_volatile_reduction((volatile int *) ADDR_VOLATILE);
  check_volatile_reduction((volatile int *) ADDR_CONST_VOLATILE);
  // Same test with imprecise pointer.
  if (nondet) ptr = (volatile int *) ADDR_CONST_VOLATILE;
  check_volatile_reduction(ptr);
}

/* We use [write_global_zero] so that values written by a test does not
   impact next test functions. */
void main (void) {
  write_global_zero();
  test_valid_pointer_reduction();
  test_pointer_reduction();
  write_global_zero();
  test_out_of_bound_access();
  write_global_zero();
  test_const();
  test_volatile();
}
