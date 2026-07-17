struct S1 {
  unsigned char f1: 7;
  unsigned short f2: 3;
} s1;

struct S2 {
  unsigned short f3: 7;
  unsigned char f4: 3;
} s2;

struct S3 {
unsigned int f5: 12;
unsigned int f6: 2;
unsigned int f7: 18;
}
__attribute__((packed))
s3;

struct S4 {
  unsigned char f0;
  unsigned long f1: 16;
  _Bool : 0;
  unsigned char f3: 7;
  unsigned int f4: 2;
  unsigned char f5: 3;
  unsigned char f6: 5;
  unsigned long long f7: 53;
  unsigned char f8: 5;
  _Bool f9: 1;
  unsigned long long f10: 18;
  unsigned long long f11: 20;
  unsigned long f12: 14;
  _Bool : 0;
  unsigned int f14: 15;
  unsigned int f15;
}
__attribute__((packed))
s4;

struct S5 {
  unsigned char f0;
  unsigned long f1: 16;
  _Bool : 0;
  unsigned char f3: 7;
  unsigned int f4: 2;
  unsigned char f5: 3;
  unsigned char f6: 5;
  unsigned long long f7: 53;
  unsigned char f8: 5;
  _Bool f9: 1;
  unsigned long long f10: 18;
  unsigned long long f11: 20;
  unsigned long f12: 14;
  _Bool : 0;
  unsigned int f14: 15;
  unsigned int f15;
}
__attribute__((packed))
s5;
