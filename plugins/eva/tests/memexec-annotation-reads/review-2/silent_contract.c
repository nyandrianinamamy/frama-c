int g,*p;
/*@ requires g == 0 || (\let z = *p; z == z); */
void f(void) { }
int main(void) { int u; p=&u; g=0; f(); }
