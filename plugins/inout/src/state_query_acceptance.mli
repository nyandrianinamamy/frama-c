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
    - [candidate]: the guard records the legacy reads of the execution and
      of each request, and the answers of the resolver of the hit log;
    - [native]: the reference, then the candidate, in one process; their
      models and values are compared with the native equality of Cvalue;
    - [wrong-producer]: the candidate, with a resolver that rebuilds each
      visit from the first producer of its function (control);
    - [trap:<phase>]: positive control. The guard aborts Eva on the first
      legacy read in this phase. For [trap:request], the driver issues one
      known request.

    The records are written as JSON lines to the file given by
    [-inout-state-query-acceptance-output], and summarized on stdout. A
    separate script compares the reference and candidate records. *)
