
/*@ region p2, \nullable;
*/
void seteq_if_notnull (int *p1, int* p2) {
    if (p2 != NULL) {
        p1 = p2 ;
    }
}
