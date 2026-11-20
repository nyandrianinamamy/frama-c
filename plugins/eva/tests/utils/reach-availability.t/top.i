/* The driver starts the analysis from a top state, because the program
   defines top_initial_state: T is reached with a known top model. */

int top_initial_state;
int g;

int main(void) {
T:
  g = 1;
  return g;
}
