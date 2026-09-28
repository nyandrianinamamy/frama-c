/*@
  assigns \result \from indirect:p;
  assigns *out \from indirect:out, p;

  behavior p_pos: // No assign in this behavior. We should use the default behavior's
                  // assigns which are \result and *out
        assumes p > 0;
        requires p % 2 == 0;

  behavior p_zero: // Assigns only \result
        assumes p == 0;
        requires out == 0;
        assigns \result \from \nothing;

  behavior p_neg: // Assigns only \result
        assumes p < 0;
        requires p % 2 == -1;
        assigns \result \from \nothing;
 */
int f(int p, char * out);

static int __counter;

/*@
  assigns __counter \from \nothing;

  behavior p_pos: // Assigns only __counter
    assumes p > 0;
    assigns __counter \from \nothing;

  behavior p_zero: // Assigns only __counter
    assumes p == 0;
    assigns __counter \from \nothing;

  behavior p_neg: // No assign here
    assumes p < 0;
    assigns \nothing;
*/
int f(int p, char * out);

