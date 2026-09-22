void f() { 
  //@ assert 0==0;
  int x;
  //@ ensures x==3;
  int y = x = 3;
  //@ ensures z == 4;
  int z = 4;
  x = z + y;
  return;
}
