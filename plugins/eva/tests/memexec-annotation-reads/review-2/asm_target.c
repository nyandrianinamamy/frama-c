int a,b,*p,first,second;
void f(void) { /*@ assigns *p; */ asm(""); }
int main(void) {
  a=1;b=2;p=&a; f();first=a;
  a=1;b=2;p=&b; f();second=b;
}
