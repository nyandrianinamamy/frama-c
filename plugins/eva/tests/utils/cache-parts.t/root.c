/* An entry point without a call: its entry, produced by a first analysis,
   answers the call of the entry point in a second analysis. */

int g;

int main(void)
{
  g = 1;
  return 0;
}
