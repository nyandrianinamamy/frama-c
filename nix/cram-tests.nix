{
  mk_tests
, cram
} :

mk_tests {
  tests-name = "cram-tests";
  tests-command = ''
    CRAM= dune runtest tests/cram
  '';
  additional-build-inputs = [ cram ];
}
