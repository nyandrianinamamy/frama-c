/* run.config
 OPT: -machdep gcc_x86_32 -print
 OPT: -kernel-msg-key=-typing:mode -machdep gcc_x86_64 -print
 OPT: -kernel-msg-key=-typing:mode -machdep gcc_x86_16 -print
EXIT: 1
 OPT:
 OPT: -kernel-msg-key=-typing:mode -machdep gcc_x86_64 -cpp-extra-args=-DFOO
 OPT: -kernel-msg-key=-typing:mode -machdep %{dep:machdep_char_unsigned.yaml}
*/

typedef unsigned int u_int8_t __attribute__ ((__mode__ (__QI__)));
typedef unsigned int u_int16_t __attribute__ ((mode (__HI__)));
typedef unsigned int u_int32_t __attribute__ ((__mode__ (SI)));
typedef unsigned int u_int64_t __attribute__ ((mode (DI)));
typedef unsigned int u_int128_t __attribute__ ((__mode__ (__TI__)));
typedef int _int8_t __attribute__ ((__mode__ (__QI__)));
typedef int _int16_t __attribute__ ((__mode__ (__HI__)));
typedef int _int32_t __attribute__ ((__mode__ (__SI__)));
typedef int _int64_t __attribute__ ((__mode__ (__DI__)));
typedef int _int128_t __attribute__ ((__mode__ (__TI__)));

typedef int register_t __attribute__ ((__mode__ (__word__)));
typedef unsigned int unsigned_register_t __attribute__ ((__mode__ (__word__)));

typedef int my_int8 __attribute__ ((__mode__ (__byte__)));
typedef unsigned int my_uint8 __attribute__ ((__mode__ (__byte__)));

typedef int my_intptr __attribute__ ((__mode__ (__pointer__)));
typedef unsigned int my_uintptr __attribute__ ((__mode__ (__pointer__)));

#ifdef FOO
// Invalid mode
typedef int foo_t __attribute__ ((__mode__ (__foo__)));
typedef int aroo_t[10] __attribute__ ((__mode__ (SI)));
// Currently unsupported mode
typedef float floo_t __attribute__ ((__mode__ (SF)));
#endif

u_int8_t u8;
u_int16_t u16;
u_int32_t u32;
u_int64_t u64;
u_int128_t u128;

_int8_t i8;
_int16_t i16;
_int32_t i32;
_int64_t i64;
_int128_t i128;

register_t foo = -42;
unsigned_register_t ufoo = 42;

my_int8 foo8 = -42;
my_uint8 foou8 = 42;

my_intptr poo = -42;
my_uintptr poou = 42;
