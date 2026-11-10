/* run.config
   DONTRUN:
*/

/* run.config_qualif
   OPT: -wp-status -wp-prover tip,alt-ergo -wp-script dry
*/

/*@ axiomatic Observer {
      predicate observe(integer x);
    }
    lemma shift_tactic_false_ko:
      \forall integer a; observe(0) ==> observe(a << 63);

    strategy OverflowShift:
      \tactic("Wp.shift", \pattern(A << 63));

    proof OverflowShift: shift_tactic_false;
*/
