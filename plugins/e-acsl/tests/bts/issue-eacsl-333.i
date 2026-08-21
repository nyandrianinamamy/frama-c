/*
  run.config
  COMMENT: issue eacsl#333: crash because of inconsistency in the annotation table
*/

char *s;

int main() {
  //@ assert \valid(s) && \initialized(s) || \length([||]) ≡ 0;
  return 0;
}
