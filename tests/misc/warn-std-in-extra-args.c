/* run.config
   OPT: -cpp-extra-args="-std=c11" -cpp-extra-args-per-file ./@PTEST_NAME@.c:-std=c11
   OPT: -cpp-extra-args="-std=c17"
   OPT: -cpp-extra-args-per-file ./@PTEST_NAME@.c:-std=c17
   OPT: -cpp-command="gcc -E -I. -std=c17" -cpp-frama-c-compliant
   OPT: -compilation-db %{dep:compile_commands_for_warn_std.json}
*/

int main(void){}
