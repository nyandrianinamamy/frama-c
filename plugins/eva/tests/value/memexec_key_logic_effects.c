/* run.config
   OPT: -eva @EVA_OPTIONS@ -main free_case
   OPT: -eva @EVA_OPTIONS@ -main free_case -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main alloc_case
   OPT: -eva @EVA_OPTIONS@ -main alloc_case -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main free_builtin_case -eva-builtin free_builtin:Frama_C_memcpy
   OPT: -eva @EVA_OPTIONS@ -main free_builtin_case -eva-builtin free_builtin:Frama_C_memcpy -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main alloc_builtin_case -eva-builtin alloc_builtin:Frama_C_memcpy
   OPT: -eva @EVA_OPTIONS@ -main alloc_builtin_case -eva-builtin alloc_builtin:Frama_C_memcpy -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main target_case -eva-builtin target_builtin:Frama_C_memcpy
   OPT: -eva @EVA_OPTIONS@ -main target_case -eva-builtin target_builtin:Frama_C_memcpy -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main source_case -eva-builtin source_builtin:Frama_C_memcpy
   OPT: -eva @EVA_OPTIONS@ -main source_case -eva-builtin source_builtin:Frama_C_memcpy -eva-no-memexec
   OPT: -eva @EVA_OPTIONS@ -main content_case -eva-builtin content_builtin:Frama_C_memcpy
   OPT: -eva @EVA_OPTIONS@ -main content_case -eva-builtin content_builtin:Frama_C_memcpy -eva-no-memexec
*/
/* run.config*
   DONTRUN:
*/
/* Eva resolves effect clauses before applying the domain's transfer. Their
   reads affect diagnostics even when frees/allocates have no cvalue effect,
   or a builtin supplies its own read/write summary. Each second call below
   must be analyzed: a hit would omit a diagnostic, or change termination.
   The memcpy builtins copy zero bytes; the relevant reads occur while Eva
   interprets their specifications. This test changes no allocation semantics. */

#include <stddef.h>

int g, x, y, a, b, *ptr, *q, answer;
char buffer;

/*@ logic int *opaque(integer n); */

/*@ assigns \nothing; frees g ? opaque(0) : &x; */
void free_spec(void);

/*@ assigns \nothing; allocates g ? opaque(0) : &x; */
void alloc_spec(void);

/*@ assigns \result \from dst; frees g ? opaque(0) : &x; */
void *free_builtin(void *dst, const void *src, size_t n);

/*@ assigns \result \from dst; allocates g ? opaque(0) : &x; */
void *alloc_builtin(void *dst, const void *src, size_t n);

void free_call(void) { free_spec(); }
void alloc_call(void) { alloc_spec(); }
void free_builtin_call(void) { free_builtin(&buffer, &buffer, 0); }
void alloc_builtin_call(void) { alloc_builtin(&buffer, &buffer, 0); }

void free_case(void) {
  g = 0; free_call();
  g = 1; free_call();
}

void alloc_case(void) {
  g = 0; alloc_call();
  g = 1; alloc_call();
}

void free_builtin_case(void) {
  g = 0; free_builtin_call();
  g = 1; free_builtin_call();
}

void alloc_builtin_case(void) {
  g = 0; alloc_builtin_call();
  g = 1; alloc_builtin_call();
}

/* Both destination and source location evaluation can emit a diagnostic. */
/*@ assigns *(g ? opaque(0) : &x) \from \nothing;
    assigns \result \from dst; */
void *target_builtin(void *dst, const void *src, size_t n);

/*@ assigns x \from *(g ? opaque(0) : &y);
    assigns \result \from dst; */
void *source_builtin(void *dst, const void *src, size_t n);

void target_call(void) { target_builtin(&buffer, &buffer, 0); }
void source_call(void) { source_builtin(&buffer, &buffer, 0); }

void target_case(void) {
  g = 0; target_call();
  g = 1; target_call();
  answer = 1;
}

void source_case(void) {
  g = 0; source_call();
  g = 1; source_call();
  answer = 1;
}

/* Source contents, not just their locations, affect the specification. The
   first specification can satisfy its ensures; the second cannot. The second
   call therefore prevents content_case from returning in either cache mode. */
/*@ assigns ptr \from q;
    assigns \result \from dst;
    ensures ptr == &b; */
void *content_builtin(void *dst, const void *src, size_t n);

void content_call(void) { content_builtin(&buffer, &buffer, 0); }

void content_case(void) {
  q = &b; ptr = 0; content_call();
  q = &a; ptr = 0; content_call();
  answer = 1;
}
