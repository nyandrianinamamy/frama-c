/* run.config
   DONTRUN:
*/
/* run.config_qualif
   OPT: -wp -wp-prover tip,alt-ergo -wp-script=dry
*/

/*@ \wp::strategy modmask_on_land:
      \tactic("Wp.modmask", \pattern(land(_,_))); */
/*@ \wp::proof modmask_on_land: trivial; */

/*@ requires 0 <= x;
    ensures \result <= x; */
unsigned trivial(int x) { return ((unsigned)x) & 255u; }
