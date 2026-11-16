{
  mk_tests
, crowbar
, python3Packages
} :

mk_tests {
  tests-name = "fuzzing-tests";
  tests-command = ''
    FC_FUZZING= dune runtest tests/fuzzing
  '';
  additional-build-inputs = [
    crowbar
    python3Packages.psutil # for dev/frama-smith.py
  ];
}
