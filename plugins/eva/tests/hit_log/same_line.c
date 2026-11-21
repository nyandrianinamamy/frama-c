/* Two calls of a function on one source line: their callstacks are printed
   alike, and are told apart by their call statements. The first call is
   analysed and the second is a hit. */

int g, h;

void f(void) { P: g = 1; }

int main(void) { f(); g = 0; h = 8; f(); return g; }
