# Crowbar tests

This folder groups some fuzzing tests, many of them relying on the
`Crowbar` OCaml library.
To run these tests the environment variable `FC_FUZZING` must be defined :

```bash
FC_FUZZING= dune test tests/fuzzing
```

If `FC_FUZZING` is defined, these tests can also be run using `dune build
@runtest`.

# Adding a test

## With Crowbar

Tests using `Crowbar` are seen as separate dune projects, so to create a new test, you must
create a directory `my_test.t` containing the following files:

- `dune-project`
- `dune`
- `run.t`
- `my_test.ml`

Except for `my_test.ml`, which contains your actual test sources, the other three can
basically be copied from existing directories (just make sure that you change the
`name` of the `test` in `dune` to match `my_test`, and, if needed, update the list of
`libraries`, especially in terms of tested plug-ins

`Crowbar` runs in qcheck mode, generating by default 5000 random inputs. If you feel like
your particular test is taking too much time, you can add an `action` field in the `test` directive
of your `dune` file, e.g. `(action (run %{test} -r 2000))` for generating 2000 random test cases

## Standalone

If your fuzzer does not use OCaml (e.g. is python-based like `bitfield.t`), there's no requirement
to have a dune project.
