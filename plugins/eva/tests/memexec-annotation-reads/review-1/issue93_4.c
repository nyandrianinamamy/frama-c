int g, answer;
void f(void) { /*@ assigns g \from \nothing; */ asm(""); }
int main(void) { g = 4; f(); g = 9; f(); answer = g; }
