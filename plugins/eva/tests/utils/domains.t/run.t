Tests the analysis on file [domains.i] with no domain and with many domains.

Only load used plugins.
  $ alias frama-c="frama-c -no-autoload-plugins -load-module eva,inout,scope"

Tests the analysis with no domain: all possible alarms are emitted.
  $ frama-c domains.i -eva -eva-domains=-cvalue
  [kernel] Parsing domains.i (no preprocessing)
  [eva] Analyzing a complete application starting at main
  [eva:initial-state] Values of globals at initialization
    NO INFORMATION
  [eva:alarm] domains.i:12: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:12: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:volatile] domains.i:13: Warning: 
    Lvalue t[i] with non-volatile-qualified type may refer to an object defined with a volatile-qualified type.
  [eva:alarm] domains.i:13: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:13: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:13: Warning: 
    accessing out of bounds index. assert 0 ≤ i;
  [eva:alarm] domains.i:13: Warning: 
    accessing out of bounds index. assert i < 100;
  [eva:alarm] domains.i:13: Warning: out of bounds write. assert \valid(&t[i]);
  [eva:alarm] domains.i:13: Warning: 
    accessing uninitialized left-value. assert \initialized(&nondet);
  [eva:alarm] domains.i:13: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&nondet);
  [eva:alarm] domains.i:12: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:12: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:12: Warning: 
    signed overflow. assert -2147483648 ≤ i + 1;
  [eva:alarm] domains.i:12: Warning: signed overflow. assert i + 1 ≤ 2147483647;
  [eva:alarm] domains.i:15: Warning: 
    accessing uninitialized left-value. assert \initialized(&t[64]);
  [eva:alarm] domains.i:15: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&t[64]);
  [eva:alarm] domains.i:18: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:18: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:19: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:19: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:20: Warning: 
    accessing uninitialized left-value. assert \initialized(&b1);
  [eva:alarm] domains.i:20: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&b1);
  [eva:alarm] domains.i:20: Warning: 
    accessing uninitialized left-value. assert \initialized(&b2);
  [eva:alarm] domains.i:20: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&b2);
  [eva:volatile] domains.i:22: Warning: 
    Lvalue t[i] with non-volatile-qualified type may refer to an object defined with a volatile-qualified type.
  [eva:alarm] domains.i:22: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:22: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:22: Warning: 
    accessing out of bounds index. assert 0 ≤ i;
  [eva:alarm] domains.i:22: Warning: 
    accessing out of bounds index. assert i < 100;
  [eva:alarm] domains.i:22: Warning: 
    accessing uninitialized left-value. assert \initialized(&t[i]);
  [eva:alarm] domains.i:22: Warning: 
    out of bounds read. assert \valid_read(&t[i]);
  [eva:alarm] domains.i:22: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&t[i]);
  [eva:volatile] domains.i:25: Warning: 
    Lvalue t[i] with non-volatile-qualified type may refer to an object defined with a volatile-qualified type.
  [eva:alarm] domains.i:25: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:25: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:25: Warning: division by zero. assert i ≢ 0;
  [eva:alarm] domains.i:25: Warning: 
    accessing out of bounds index. assert 0 ≤ i;
  [eva:alarm] domains.i:25: Warning: 
    accessing out of bounds index. assert i < 100;
  [eva:alarm] domains.i:25: Warning: 
    accessing uninitialized left-value. assert \initialized(&t[i]);
  [eva:alarm] domains.i:25: Warning: 
    out of bounds read. assert \valid_read(&t[i]);
  [eva:alarm] domains.i:25: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&t[i]);
  [eva:alarm] domains.i:25: Warning: 
    signed overflow. assert t[i] / i ≤ 2147483647;
  [eva:volatile] domains.i:26: Warning: 
    Lvalue t[i] with non-volatile-qualified type may refer to an object defined with a volatile-qualified type.
  [eva:alarm] domains.i:26: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:26: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:26: Warning: division by zero. assert i ≢ 0;
  [eva:alarm] domains.i:26: Warning: 
    accessing out of bounds index. assert 0 ≤ i;
  [eva:alarm] domains.i:26: Warning: 
    accessing out of bounds index. assert i < 100;
  [eva:alarm] domains.i:26: Warning: 
    accessing uninitialized left-value. assert \initialized(&t[i]);
  [eva:alarm] domains.i:26: Warning: 
    out of bounds read. assert \valid_read(&t[i]);
  [eva:alarm] domains.i:26: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&t[i]);
  [eva:alarm] domains.i:26: Warning: 
    signed overflow. assert t[i] / i ≤ 2147483647;
  [eva:alarm] domains.i:26: Warning: 
    signed overflow. assert -2147483648 ≤ (int)(t[i] / i) + 1;
  [eva:alarm] domains.i:26: Warning: 
    signed overflow. assert (int)(t[i] / i) + 1 ≤ 2147483647;
  [eva:alarm] domains.i:30: Warning: 
    accessing uninitialized left-value. assert \initialized(&k);
  [eva:alarm] domains.i:30: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&k);
  [eva:alarm] domains.i:30: Warning: 
    accessing uninitialized left-value. assert \initialized(&nondet);
  [eva:alarm] domains.i:30: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&nondet);
  [eva:alarm] domains.i:31: Warning: 
    accessing uninitialized left-value. assert \initialized(&k);
  [eva:alarm] domains.i:31: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&k);
  [eva:alarm] domains.i:31: Warning: 
    signed overflow. assert -2147483648 ≤ k + 1;
  [eva:alarm] domains.i:31: Warning: signed overflow. assert k + 1 ≤ 2147483647;
  [eva:alarm] domains.i:32: Warning: 
    accessing uninitialized left-value. assert \initialized(&j);
  [eva:alarm] domains.i:32: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&j);
  [eva:alarm] domains.i:32: Warning: 
    signed overflow. assert -2147483648 ≤ j + 1;
  [eva:alarm] domains.i:32: Warning: signed overflow. assert j + 1 ≤ 2147483647;
  [eva:alarm] domains.i:35: Warning: 
    accessing uninitialized left-value. assert \initialized(&i);
  [eva:alarm] domains.i:35: Warning: 
    accessing uninitialized left-value. assert \initialized(&j);
  [eva:alarm] domains.i:35: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&i);
  [eva:alarm] domains.i:35: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&j);
  [eva:alarm] domains.i:35: Warning: 
    signed overflow. assert -2147483648 ≤ i - j;
  [eva:alarm] domains.i:35: Warning: signed overflow. assert i - j ≤ 2147483647;
  [eva:alarm] domains.i:35: Warning: 
    signed overflow. assert -2147483648 ≤ (int)(i - j) + 1;
  [eva:alarm] domains.i:35: Warning: 
    signed overflow. assert (int)(i - j) + 1 ≤ 2147483647;
  [eva:alarm] domains.i:36: Warning: 
    accessing uninitialized left-value. assert \initialized(&j);
  [eva:alarm] domains.i:36: Warning: 
    accessing uninitialized left-value. assert \initialized(&r);
  [eva:alarm] domains.i:36: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&j);
  [eva:alarm] domains.i:36: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&r);
  [eva:alarm] domains.i:36: Warning: 
    signed overflow. assert -2147483648 ≤ r + j;
  [eva:alarm] domains.i:36: Warning: signed overflow. assert r + j ≤ 2147483647;
  [eva:volatile] domains.i:37: Warning: 
    Lvalue t[k - 1] with non-volatile-qualified type may refer to an object defined with a volatile-qualified type.
  [eva:alarm] domains.i:37: Warning: 
    accessing uninitialized left-value. assert \initialized(&k);
  [eva:alarm] domains.i:37: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&k);
  [eva:alarm] domains.i:37: Warning: 
    accessing out of bounds index. assert 0 ≤ (int)(k - 1);
  [eva:alarm] domains.i:37: Warning: 
    accessing out of bounds index. assert (int)(k - 1) < 100;
  [eva:alarm] domains.i:37: Warning: 
    signed overflow. assert -2147483648 ≤ k - 1;
  [eva:alarm] domains.i:37: Warning: signed overflow. assert k - 1 ≤ 2147483647;
  [eva:alarm] domains.i:37: Warning: 
    accessing uninitialized left-value. assert \initialized(&t[(int)(k - 1)]);
  [eva:alarm] domains.i:37: Warning: 
    out of bounds read. assert \valid_read(&t[(int)(k - 1)]);
  [eva:alarm] domains.i:37: Warning: 
    accessing left-value that contains escaping addresses.
    assert ¬\dangling(&t[(int)(k - 1)]);
  [eva:alarm] domains.i:39: Warning: 
    accessing uninitialized left-value. assert \initialized(&a);
  [eva:alarm] domains.i:39: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&a);
  [eva:alarm] domains.i:40: Warning: 
    accessing uninitialized left-value. assert \initialized(&a);
  [eva:alarm] domains.i:40: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&a);
  [eva:alarm] domains.i:40: Warning: division by zero. assert a ≢ 0;
  [eva:alarm] domains.i:42: Warning: 
    accessing uninitialized left-value. assert \initialized(&a);
  [eva:alarm] domains.i:42: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&a);
  [eva:alarm] domains.i:43: Warning: 
    accessing uninitialized left-value. assert \initialized(&a);
  [eva:alarm] domains.i:43: Warning: 
    accessing left-value that contains escaping addresses. assert ¬\dangling(&a);
  [eva:alarm] domains.i:43: Warning: division by zero. assert a ≢ 0;
  [eva:show] domains.i:46: 
    Frama_C_domain_show_each:
    a : 
    i : 
    j : 
    k : 
    r :
  [eva:show] domains.i:47: 
    Frama_C_dump_each:
    ==END OF DUMP==
  [eva:show] domains.i:48: Dumping state in file 'domains_dump_0'
  [eva:show] domains.i:53: 
    Frama_C_domain_show_each:
    scalar :
  [scope:rm_asserts] removing 15 assertion(s)
  [eva:summary] ====== ANALYSIS SUMMARY ======
    ----------------------------------------------------------------------------
    1 function analyzed (out of 1): 100% coverage.
    In this function, 41 statements reached (out of 41): 100% coverage.
    ----------------------------------------------------------------------------
    Some errors and warnings have been raised during the analysis:
      by the Eva analyzer:      0 errors    5 warnings
      by the Frama-C kernel:    0 errors    0 warnings
    ----------------------------------------------------------------------------
    95 alarms generated by the analysis:
        29 accesses to uninitialized left-values
        29 escaping addresses
        18 integer overflows
        10 accesses out of bounds index
         5 invalid memory accesses
         4 divisions by zero
    ----------------------------------------------------------------------------
    No logical properties have been reached by the analysis.
    ----------------------------------------------------------------------------

Tests the analysis with many domains: no alarm is emitted.
  $ frama-c domains.i -eva \
  > -eva-domains sign,equality,bitwise,symbolic-locations,gauges,octagon,multidim \
  > -eva-msg-key=d-equality,d-symbolic-locations,d-gauges,d-octagon,d-multidim,d-bitwise,d-sign \
  > -eva-warn-key experimental=inactive
  [kernel] Parsing domains.i (no preprocessing)
  [eva] Analyzing a complete application starting at main
  [eva:initial-state] Values of globals at initialization
    nondet ∈ [--..--]
  [eva:partition] domains.i:12: starting to merge loop iterations
  [eva:partition] domains.i:30: starting to merge loop iterations
  [eva:show] domains.i:46: 
    Frama_C_domain_show_each:
    a : # cvalue: {8}
        # symbolic-locations: (not implemented)
        # equality: 
        # octagon: (not implemented)
        # gauges: (not implemented)
        # multidim: {8}
        # bitwise: (not implemented)
        # sign: +
    i : # cvalue: [1..99]
        # symbolic-locations: (not implemented)
        # equality: 
        # octagon: (not implemented)
        # gauges: (not implemented)
        # multidim: [1..99]
        # bitwise: (not implemented)
        # sign: +
    j : # cvalue: [10..210]
        # symbolic-locations: (not implemented)
        # equality: 
        # octagon: (not implemented)
        # gauges: (not implemented)
        # multidim: [10..210]
        # bitwise: (not implemented)
        # sign: +
    k : # cvalue: [2..100]
        # symbolic-locations: (not implemented)
        # equality: {k = ((i - j) + 1) + j}
        # octagon: (not implemented)
        # gauges: (not implemented)
        # multidim: [2..100]
        # bitwise: (not implemented)
        # sign: -0+
    r : # cvalue: {1}
        # symbolic-locations: (not implemented)
        # equality: 
        # octagon: (not implemented)
        # gauges: (not implemented)
        # multidim: {1}
        # bitwise: (not implemented)
        # sign: 0+
  [eva:show] domains.i:47: 
    Frama_C_dump_each:
    # cvalue:
    nondet ∈ [--..--]
    a ∈ {8}
    i ∈ [1..99]
    j ∈ [10..210]
    k ∈ [2..100]
    r ∈ {1}
    t[0..63] ∈ [--..--] or UNINITIALIZED
     [64] ∈ [--..--]
     [65..99] ∈ [--..--] or UNINITIALIZED
    b1 ∈ {0; 1}
    b2 ∈ {0; 1}
    scalar ∈ UNINITIALIZED
    # symbolic-locations:
    V: {[ t[i] -> [-2147483648..2147483647]
          t[i] / i -> [-2147483648..2147483647]
          i - j -> [-209..89]
          t[k - 1] -> [-2147483648..2147483647] ]}
    Z: {[ t[i] -> i; t[1..99]
          t[i] / i -> i; t[1..99]
          i - j -> i; j
          t[k - 1] -> k; t[1..99] ]}
    I: {[ i -> {t[i], t[i] / i, i - j}
          j -> {i - j}
          k -> {t[k - 1]}
          t -> {t[i], t[i] / i, t[k - 1]} ]}
    S: {[ i -> {t[i], t[i] / i, i - j}
          j -> {i - j}
          k -> {t[k - 1]}
          t -> {t[i], t[i] / i, t[k - 1]} ]}
    # equality:
    {k = ((i - j) + 1) + j}
    # octagon:
    {[ i + j ∈ [11..309]
       j + k ∈ [12..310]
       j - k ∈ [-90..208]
        ]}
    # gauges:
    V: [{[ a -> {8}
           i -> [-2147483648..2147483647]
           j -> [10..210]
           k -> [-2147483847..2147483848]
           r -> {1}
           b1 -> {0; 1}
           b2 -> {0; 1} ]}]
    
    # multidim:
    a -> {8}
    i -> [1..99]
    j -> [10..210]
    k -> [2..100]
    r -> {1}
    t -> {
           [0 .. 63] = [-2147483648..2147483647],
           [64] = [-2147483648..2147483647],
           [65 .. 99] = [-2147483648..2147483647]
         }
    b1 -> {0; 1}
    b2 -> {0; 1}
    scalar -> UNINITIALIZED
    # bitwise:
    a[bits 0 to 2] ∈ {0}
     [bits 3 to 3] ∈ {1}
     [bits 4 to 31] ∈ {0}
    # sign:
    {[ a -> +
       i -> +
       j -> +
       r -> 0+ ]}
    ==END OF DUMP==
  [eva:show] domains.i:48: Dumping state in file 'domains_dump_0'
  [eva:show] domains.i:53: 
    Frama_C_domain_show_each:
    scalar : # cvalue: [bits 0 to 7]# ∈ {65537}%32, bits 0 to 7 
                       [bits 8 to 15] ∈ {42}
                       [bits 16 to 31]# ∈ {65537}%32, bits 16 to 31 
                       This amounts to: {76289}
             # symbolic-locations: (not implemented)
             # equality: 
             # octagon: (not implemented)
             # gauges: (not implemented)
             # multidim: T
             # bitwise: (not implemented)
             # sign: -0+
  [eva] ====== VALUES COMPUTED ======
  [eva:final-states] Values at end of function main:
    a ∈ {8}
    i ∈ [1..99]
    j ∈ [10..210]
    k ∈ [2..100]
    r ∈ {1}
    t[0..63] ∈ [--..--] or UNINITIALIZED
     [64] ∈ [--..--]
     [65..99] ∈ [--..--] or UNINITIALIZED
    b1 ∈ {0; 1}
    b2 ∈ {0; 1}
    scalar[bits 0 to 7]# ∈ {65537}%32, bits 0 to 7 
          [bits 8 to 15] ∈ {42}
          [bits 16 to 31]# ∈ {65537}%32, bits 16 to 31 
  [eva:summary] ====== ANALYSIS SUMMARY ======
    ----------------------------------------------------------------------------
    1 function analyzed (out of 1): 100% coverage.
    In this function, 41 statements reached (out of 41): 100% coverage.
    ----------------------------------------------------------------------------
    No errors or warnings raised during the analysis.
    ----------------------------------------------------------------------------
    0 alarms generated by the analysis.
    ----------------------------------------------------------------------------
    No logical properties have been reached by the analysis.
    ----------------------------------------------------------------------------


Check content of file "domains_dump_0" generated by the
Frama_C_dump_each_file_domains_dump directive.
  $ cat domains_dump_0
  DUMPING STATE at "domains.i", line 48, characters 3-40
  # cvalue:
  nondet ∈ [--..--]
  a ∈ {8}
  i ∈ [1..99]
  j ∈ [10..210]
  k ∈ [2..100]
  r ∈ {1}
  t[0..63] ∈ [--..--] or UNINITIALIZED
   [64] ∈ [--..--]
   [65..99] ∈ [--..--] or UNINITIALIZED
  b1 ∈ {0; 1}
  b2 ∈ {0; 1}
  scalar ∈ UNINITIALIZED
  # symbolic-locations:
  V: {[ t[i] -> [-2147483648..2147483647]
        t[i] / i -> [-2147483648..2147483647]
        i - j -> [-209..89]
        t[k - 1] -> [-2147483648..2147483647] ]}
  Z: {[ t[i] -> i; t[1..99]
        t[i] / i -> i; t[1..99]
        i - j -> i; j
        t[k - 1] -> k; t[1..99] ]}
  I: {[ i -> {t[i], t[i] / i, i - j}
        j -> {i - j}
        k -> {t[k - 1]}
        t -> {t[i], t[i] / i, t[k - 1]} ]}
  S: {[ i -> {t[i], t[i] / i, i - j}
        j -> {i - j}
        k -> {t[k - 1]}
        t -> {t[i], t[i] / i, t[k - 1]} ]}
  # equality:
  {k = ((i - j) + 1) + j}
  # octagon:
  {[ i + j ∈ [11..309]
     j + k ∈ [12..310]
     j - k ∈ [-90..208]
      ]}
  # gauges:
  V: [{[ a -> {8}
         i -> [-2147483648..2147483647]
         j -> [10..210]
         k -> [-2147483847..2147483848]
         r -> {1}
         b1 -> {0; 1}
         b2 -> {0; 1} ]}]
  
  # multidim:
  a -> {8}
  i -> [1..99]
  j -> [10..210]
  k -> [2..100]
  r -> {1}
  t -> {
         [0 .. 63] = [-2147483648..2147483647],
         [64] = [-2147483648..2147483647],
         [65 .. 99] = [-2147483648..2147483647]
       }
  b1 -> {0; 1}
  b2 -> {0; 1}
  scalar -> UNINITIALIZED
  # bitwise:
  a[bits 0 to 2] ∈ {0}
   [bits 3 to 3] ∈ {1}
   [bits 4 to 31] ∈ {0}
  # sign:
  {[ a -> +
     i -> +
     j -> +
     r -> 0+ ]}

