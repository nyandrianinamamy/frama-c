/* run.config
   STDOPT:
   PLUGIN: eva,inout,scope
   STDOPT: +"-eva-verbose 1 -eva-msg-key=final-states -eva-remove-redundant-alarms"
*/

/* The worked example of #87. The matching key of f is {c, g}; h is in the
   frame. Call A (line 24) and call C (line 26) are analysed; call B
   (line 25) is a hit of the entry of A, call D (line 27) a hit of the entry
   of C. Expected, on the callstacks A, B, C, D and joined:
   - g at the start of f: {4}, {4}, {9}, {9}, {4; 9};
   - g before P: {0; 4}, {0; 4}, {0; 9}, {0; 9}, {0; 4; 9};
   - g after g = 1 and at the return: {1} everywhere;
   - h at every point of f: {7}, {8}, {8}, {5}, {5; 7; 8}. */

#include "__fc_builtin.h"

int c, g, h;

void f(void) { if (c) g = 0; P: g = 1; }

int main(void) {
  c = Frama_C_interval(0, 1);
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
  g = 9; h = 5; f();
  return 0;
}
