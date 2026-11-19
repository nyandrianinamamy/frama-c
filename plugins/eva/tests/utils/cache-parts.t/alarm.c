/* parts.c with an alarm in main, for a reader that starts from the alarms:
   the main function of parts.c is called by this one, which then divides
   by a volatile value. */

#define main parts_main
#include "parts.c"
#undef main

int main(void)
{
  int r = parts_main();
  out = 10 / any;
  return r;
}
