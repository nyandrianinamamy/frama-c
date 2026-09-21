Test of Eva abort messages.

Load test_request and used plugins, and define shared options.
  $ alias frama-c="frama-c abort.i \
  > -no-autoload-plugins -load-module eva,inout,scope \
  > -eva -eva-verbose 1"

Test abort message on calls through function pointers when the cvalue domain
is disabled.
  $ frama-c -main top_function_pointer -eva-domains=-cvalue -eva-warn-key alarm=inactive
  [kernel] Parsing abort.i (no preprocessing)
  [eva] Analyzing a complete application starting at top_function_pointer
  [eva] abort.i:11: User Error: 
    Calls through function pointers are not supported without the cvalue domain.
  [eva:volatile] abort.i:11: Warning: 
    Lvalue *fptr_0 with non-volatile-qualified type may refer to an object defined with a volatile-qualified type.
  [kernel] Plug-in eva aborted: invalid user input.
  [1]
