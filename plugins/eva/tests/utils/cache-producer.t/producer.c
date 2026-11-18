int p = 3, q = 4, out, keep, answer;

int leaf(void)
{
  out = p + q;
  return 2;
}

int main(void)
{
  answer = leaf();
  keep = 42;
  answer = leaf();
  return 0;
}

void two_blocks(void)
{
  out = p + q;
}

int pair[2] = {1, 3};

void partial(void)
{
  pair[0] = 7;
}

void inner_scope(void)
{
  if (p) {
    int local;
    out = q;
  }
}

void swept(void)
{
  if (p) {
    int local = q;
    out = local;
  }
}

/*@ requires p > 0; */
void precondition(void)
{
  out = q;
}

int g;

void read_g(void)
{
  out = g;
}

void repeated(void)
{
  for (int i = 1; i <= 2; ++i) {
    g = i;
    read_g();
  }
}
