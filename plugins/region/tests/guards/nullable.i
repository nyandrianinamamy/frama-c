/* run.config
    OPT: -region -region-msg-key dump -print
*/


int seteq_if_notnull (int *p1, int* p2) {
    if (p2) {
        *p1 = *p2 ;
    }
    return *p1;
}

int* shift(int *p, int k) {
    return 0 <= k ? (p + k) : 0 ;
}

int f(int *p) {
    return p ? *p : 42;
}
