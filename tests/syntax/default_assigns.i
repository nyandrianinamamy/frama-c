/*@
  assigns \result \from indirect:p;
  assigns *out \from indirect:out, p;

  behavior p_pos: // Pas d'assigns dans ce behavior. Le behavior
                  // par défaut nous indique qu'il assigns \result
                  // et *out
        assumes p > 0;
        requires p % 2 == 0;

  behavior p_zero: // Assigns seulement \result
        assumes p == 0;
        requires out == 0;
        assigns \result \from \nothing;

  behavior p_neg: // Assigns seulement \result
        assumes p < 0;
        requires p % 2 == -1;
        assigns \result \from \nothing;
 */
int f(int p, char * out);

static int __counter;

/*@
  assigns __counter \from \nothing;

  behavior p_pos: // Ajout d'un assigns de __counter
    assumes p > 0;
    assigns __counter \from \nothing;

  behavior p_zero: // Ajout d'un assigns de __counter
    assumes p == 0;
    assigns __counter \from \nothing;

  behavior p_neg: // Pas d'assigns de __counter ici
    assumes p < 0;
    assigns \nothing;
*/
int f(int p, char * out);

