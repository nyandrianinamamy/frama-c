/* run.config*
   STDOPT: #""
   STDOPT: #"-no-warn-left-shift-negative -warn-right-shift-negative"
*/

/* The first run emits alarms on left shifts on negative values;
   the second run emits alarms on right shifts on negative values. */

#include "__fc_builtin.h"

volatile int rand;

/* Tests left and right shift of negative integers. */
void main() {
  int x, y, r;
  // no alarm
  x = Frama_C_interval(24, 128);
  r = x >> 4;
  r = x << 4;
  // alarm and reduction of [x]
  x = Frama_C_interval(-8, 12);
  r = x << 2;
  Frama_C_show_each_left_shift(x, r);
  x = Frama_C_interval(-8, 12);
  r = x >> 2;
  Frama_C_show_each_right_shift(x, r);
  // invalid alarm
  if (rand) {
    int k = (-44) << 15;
    int l = (-44) << 3;
    Frama_C_show_each_neg_left_shift(k, l);
  }
  if (rand) {
    int i = (-44) >> 15;
    int j = (-44) >> 3;
    Frama_C_show_each_neg_right_shift(i, j);
  }
  // Singleton values.
  Frama_C_show_each(-3, ">>", 2, "=", -3 >> 2);
  Frama_C_show_each(-63, ">>", 2, "=", -63 >> 2);
  Frama_C_show_each(-64, ">>", 2, "=", -64 >> 2);
  Frama_C_show_each(-65, ">>", 2, "=", -65 >> 2);
  // The first operand is an interval.
  x = Frama_C_interval(-65, -3);
  Frama_C_show_each(x, ">>", 2, "=", x >> 2);
  // The second operand is an interval.
  y = Frama_C_interval(2, 10);
  Frama_C_show_each(-3, ">>", y, "=", -3 >> y);
  Frama_C_show_each(-63, ">>", y, "=", -63 >> y);
  Frama_C_show_each(-64, ">>", y, "=", -64 >> y);
  Frama_C_show_each(-65, ">>", y, "=", -65 >> y);
  // Both operands are intervals.
  Frama_C_show_each(x, ">>", y, "=", x >> y);
  // Only the first interval crosses zero.
  int xz = Frama_C_interval(-65, 3);
  Frama_C_show_each(xz, ">>", y, "=", xz >> y);
  // Only the second interval crosses zero.
  int yz = Frama_C_interval(-2, 10);
  Frama_C_show_each(x, ">>", yz, "=", x >> yz);
  // Both intervals cross zero.
  Frama_C_show_each(xz, ">>", yz, "=", xz >> yz);
}
