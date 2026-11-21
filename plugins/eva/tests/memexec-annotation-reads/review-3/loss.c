int x, *p, answer;
/*@ assigns p \from &x; */
void f(void) { p = &x; }
int main(void) { p = 0; f(); p = 0; f(); answer = p == &x; }
