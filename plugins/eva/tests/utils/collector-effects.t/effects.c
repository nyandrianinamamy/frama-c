int *holder;
int flag = 1;

void swept(void)
{
  if (flag) {
    int local;
    holder = &local;
  }
}

int recur(int n)
{
  return n > 0 ? recur(n - 1) : n;
}

int start_recursion(void)
{
  return recur(2);
}

int *outer_holder;

void callee(void)
{
  int local;
  outer_holder = &local;
}

void foreign_sweep(void)
{
  callee();
}

void threaded(void)
{
  flag = 0;
}

void Frama_C_dump_each(void);
void show(void)
{
  Frama_C_dump_each();
}

int divisor;
int alarm(void)
{
  return 10 / divisor;
}

void Frama_C_watch_value(int *, int, int, int);
void install_watchpoint(void)
{
  Frama_C_watch_value(&flag, sizeof(flag), 17, 0);
}

void watched(void)
{
  flag = 17;
}

void start_watchpoint(void)
{
  install_watchpoint();
  watched();
}

int *untouched;

void call_swept(void)
{
  swept();
}

void middle(void)
{
  threaded();
}

void outer(void)
{
  middle();
}
