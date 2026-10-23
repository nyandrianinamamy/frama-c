volatile double v;
volatile unsigned int nondet;

/*@ requires \is_finite(d);
    requires (0.0 < d < 0x1p-1022);
    assigns \nothing; */
void assert_subnormal(double d);

/* Tests an edge case of backward_cast_float_to_double. */
void test_backward_cast_float_to_double (void) {
  float f = v;
  /* assert_subnormal reduces its double argument to a range of values without
     single precision values. The backward propagation of this reduction to the
     concrete argument [f] (which is a float) should lead to bottom. */
  if (nondet) {
    assert_subnormal(f);
    Frama_C_show_each_bottom("UNREACHABLE");
  }
}

/* Tests the soundness of the backward reduction from double to float. */
void test_backward_cast_double_to_float (void) {
  double d = v;
  // Avoid alarms on cast to float.
  if (d > 100. || d < -100.) return;
  if ((float)d == 1.5f) {
    /* Must include all double precision values around 1.5 that are rounded
       to 1.5 in single precision. */
    Frama_C_show_each(d);
  }
  if ((float)d <= 0.75f && (float)d >= -0.75f) {
    /* Must also include all double precision values above 0.75 and below -0.75
       that are rounded to 0.75 or -0.75 in single precision. */
    Frama_C_show_each(d);
  }
  if ((float)d < 0.75f && (float)d > -0.75f) {
    /* Must also include all double precision values below 0.75 and above -0.75
       that are rounded to the the float previous to 0.75 or next to -0.75. */
    Frama_C_show_each(d);
  }
}

/* Tests the soundness of the backward reduction of cast from int to float
   around the first integer not representable by a float32. */
void test_backward_cast_int_to_float (void) {

  int i = 16777217; // First integer not representable by a float32

  Frama_C_show_each_float_16777215((float)(i-2));
  Frama_C_show_each_float_16777216((float)(i-1));
  Frama_C_show_each_float_16777217((float)i);
  Frama_C_show_each_float_16777218((float)(i+1));

  i = nondet % 20000001;
  if ((float)i == 16777215.f) {
    Frama_C_show_each_reduced_16777215(i); // must include 16777215
  }
  if ((float)i == 16777216.f) {
    // must include 16777216 and 16777217; imprecise for now.
    Frama_C_show_each_not_singleton(i);
  }

  /* Same with relational operators. */
  if ((float)i < 16777216.f) {
    Frama_C_show_each_bound_16777215(i);
  }
  if ((float)i <= 16777216.f) {
    // must also include 16777217; imprecise for now.
    Frama_C_show_each_bound_16777217(i);
  }

  /* Same with negative values. */
  i = -i;
  if ((float)i == -16777215.f) {
    Frama_C_show_each_reduced_neg_16777215(i); // must include -16777215
  }
  if ((float)i == -16777216.f) {
    // must include -16777216 and -16777217; imprecise for now.
    Frama_C_show_each_not_singleton(i);
  }
}

/* Tests interpretation of conversion from integers to floating-point values
   when the integer is not representable as a double. */
void test_forward_cast_int_to_float (void) {
  // 2^53 + 1 is the first integer not representable as a double.
  double vd = 0x1p53;
  long long vl = (long long)vd + 1;
  // In floating-point semantics, both are equal (vl is rounded down to vd).
  Frama_C_show_each_0(vl > vd);
  Frama_C_show_each_1(vl == vd);
  // In ACSL real semantics, vl is greater than vd.
  /*@ check true: vl > vd; */
  // Same with negative numbers.
  vl = - vl;
  vd = -vd;
  Frama_C_show_each_0(vl < vd);
  Frama_C_show_each_1(vl == vd);
  /*@ check true: vl < vd; */
}


void main (void) {
  test_backward_cast_float_to_double();
  test_backward_cast_double_to_float ();
  test_backward_cast_int_to_float();
  test_forward_cast_int_to_float();
}
