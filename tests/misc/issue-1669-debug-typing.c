/* run.config
  OPT: -kernel-msg-key typing
*/

__builtin_va_list va;

void vf(char *s, ...) {
  __builtin_va_start(va, s);
}
