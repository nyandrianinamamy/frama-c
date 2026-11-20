/* A function pointer read in a body that makes no call: the server request
   of the functions it points to reads the state before the statement. */

int target(void) { return 42; }

int body(int (*p)(void))
{
  return p != 0;
}

int main(void)
{
  return body(&target);
}
