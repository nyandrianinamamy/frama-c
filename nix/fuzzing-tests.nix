{
  mk_tests
, crowbar
} :

mk_tests {
  tests-name = "fuzzing-tests";
  tests-command = ''
    FC_FUZZING= dune runtest tests/fuzzing
  '';
  additional-build-inputs = [ crowbar ];
}
