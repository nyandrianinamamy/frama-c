# Inputs of the reviews of the parked correction

This branch holds an attempt to add to the key of memexec the memory that
Eva reads through annotations and contracts. It was stopped after three
reviews; issue #97 of the fork gives the index of the cases and the open
defects.

- `scan/`: two programs found before the first review.
- `review-1/`: inputs of the first review (programs of #86, #93 to #96,
  and the three-call program `regression.c`).
- `review-2/`: inputs of the second review; `results.txt` has its results
  on `dev` and on `d84d3149e4`, `results-after-round-3.txt` those on
  `0ea12c8e3d`.
- `review-3/`: inputs and report of the third review, on `0ea12c8e3d`.
  The paths in the report are those of the reviewer's machine.

Each program is run twice and the final states compared:

    frama-c -no-autoload-plugins -load-module eva,inout -eva \
      -eva-show-progress file.c
    frama-c -no-autoload-plugins -load-module eva,inout -eva \
      -eva-show-progress -eva-no-memexec file.c

`issue94_*.c` also take `-eva-slevel 20 -eva-no-alloc-returns-null`,
`recursive.c` takes `-eva-unroll-recursive-calls 2`, and `spec.c` takes
`-eva-builtin choose:Frama_C_memcpy`.
