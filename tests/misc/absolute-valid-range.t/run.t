Test error and warning messages on invalid -absolute-valid-range arguments.

Do not load any plug-ins.
  $ alias="frama-c -no-autoload-plugins"

Argument is not an integer range.
  $ frama-c -absolute-valid-range foobar
  [kernel] User Error: Invalid -absolute-valid-range argument. Expected a comma-separated list of integer ranges min-max with optional const or volatile qualifiers. Each integer may be in decimal, hexadecimal (0x, 0X), octal (0o) or binary (0b) notation.
    A correct example is 1024-1423,0x800-0x81F:const,0x1000-0x101F:volatile.
    Error is: "Invalid_argument(\"Z.of_substring_base: invalid digit\")"
  [kernel] Frama-C aborted: invalid user input.
  [1]

Empty range: minimum address larger than maximum address.
  $ frama-c -absolute-valid-range 1025-1024
  [kernel] User Error: Invalid empty range 1025-1024 specified by -absolute-valid-range
  [kernel] Frama-C aborted: invalid user input.
  [1]

Accept singleton range.
  $ frama-c -absolute-valid-range 1024-1024

Overlapping ranges.
  $ frama-c -absolute-valid-range 0x400-0x420,0x420-0x440
  [kernel] User Error: Invalid overlapping ranges 0x400-0x420 and 0x420-0x440 specified by -absolute-valid-range
  [kernel] Frama-C aborted: invalid user input.
  [1]

Unknown qualifier.
  $ frama-c -absolute-valid-range 1024-1055:foobar
  [kernel] User Error: Invalid -absolute-valid-range qualifier "foobar".
  [kernel] Frama-C aborted: invalid user input.
  [1]

Same ranges with different qualifiers.
  $ frama-c -absolute-valid-range 0x400-0x41F -absolute-valid-range 0x400-0x41F:volatile
  [kernel] User Error: Invalid overlapping ranges 0x400-0x41F and 0x400-0x41F:volatile specified by -absolute-valid-range
  [kernel] Frama-C aborted: invalid user input.
  [1]

Accept repetition of the same range with the same qualifiers.
  $ frama-c -absolute-valid-range 0x400-0x41F:volatile -absolute-valid-range 0x400-0x41F:volatile

Warning: range contains the NULL pointer.
  $ frama-c -absolute-valid-range 0-0xFF
  [kernel] Warning: Absolute valid range 0-0xFF includes NULL pointer 0.
