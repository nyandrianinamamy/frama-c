(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Acceptance driver for Eva result queries (prototype).

    Enabled by [-inout-state-query-acceptance]. It runs Eva, then a fixed
    set of public requests built around the statement labelled [P], and
    prints one record per request. The modes are:
    - [reference]: fresh-only Eva (memexec off) on the legacy path (hit log
      off), legacy-read guard off;
    - [candidate]: the guard is armed once, before the analysis, with the
      trap of every phase: any legacy read aborts Eva. The answers of the
      resolver of the hit log are recorded;
    - [record]: the guard logs every legacy read and traps none;
    - [native]: the reference, then the candidate, in one process; their
      models and values are compared with the native equality of Cvalue;
    - [wrong-producer]: the candidate, with a resolver that rebuilds each
      visit from the first producer of its function (control);
    - [tail-probe]: the candidate, then one request on cleared results,
      which must abort (control);
    - [store-check]: the hit log records, then declines every request,
      which reads the legacy tables (control);
    - [perturb-calls]: the hit log exports wrong statuses and callers
      (control);
    - [restore-check]: the hit log declines every request once a snapshot
      of the results is restored (control);
    - [trap:<phase>]: positive control. The guard aborts Eva on the first
      legacy read in this phase. For [trap:request], the driver issues one
      known request.

    The prefix [reach-] selects the reachability battery, on every labelled
    statement, and [plugins-] the battery of the plug-in readers and of
    Eva's semantic reports. The records are written as JSON lines to the
    file given by [-inout-state-query-acceptance-output], and summarized on
    stdout. A separate script compares the reference and candidate
    records. *)
