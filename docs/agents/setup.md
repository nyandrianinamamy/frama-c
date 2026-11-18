# Setting up or repairing the local switch

Read this when the checkout has no `_opam/` directory, or when
`bash dev/check-env.sh` fails. The versions it expects are OCaml 5.2.1 and
Dune 3.21.1.

## Creating the switch

The [opam](../../opam) file requires OCaml >= 5.2.0 and Dune > 3.15.0.
[INSTALL.md](../../INSTALL.md#full-compilation-guide) is the general guide.
On Ubuntu 24.04, use a **local** switch so other checkouts keep their compilers:

```sh
# System dependencies (requires sudo; installs packages, not a system upgrade).
sudo apt-get install -y --no-install-recommends build-essential gcc-multilib \
  autoconf m4 \
  pkg-config git curl unzip patch libgmp-dev libmpfr-dev zlib1g-dev \
  graphviz time clang yq socat dos2unix libzmq3-dev \
  python3-venv jq cmake libclang-cpp-dev libclang-dev llvm-dev
opam update
opam switch create . ocaml-base-compiler.5.2.1 --no-install -y --jobs=8
eval "$(opam env --switch=. --set-switch)"
opam install --switch=. dune.3.21.1 -y --jobs=8
opam pin add --switch=. dune 3.21.1 --no-action -y
opam install --switch=. --deps-only --with-test . -y --jobs=8
DUNE_ROOT=. opam install --switch=. -y --jobs=8 apron zmq ocp-indent.1.10.0 \
  headache camomile alt-ergo.2.6.4 mopsa.1.2
```

`--no-install` defers the repository packages, not the compiler. Setup fetches
and builds packages. Do not rely on an inherited `OPAM_SWITCH_PREFIX` from
another checkout. Python test tools can be isolated inside the ignored switch
directory:

```sh
python3 -m venv _opam/setup-venv
_opam/setup-venv/bin/pip install check-jsonschema==0.39.0 PyYAML==6.0.3 \
  black==26.10.1 clang-format==21.1.8
```

## Why each piece is there

- **Dune 3.21.1, pinned.** With Dune 3.25.0,
  `tests/fc_script/estimate-difficulty.t` fails: the script starts `frama-c`
  through `_build/install/default/.packages/<hash>/bin/frama-c`, which exits
  at startup with `Failure("hd")` because it does not find its share
  directory. Mopsa 1.2 also constrains Dune to < 3.22, and installing Dune
  first avoids rebuilding its dependents.
- **`DUNE_ROOT=.`** keeps Mopsa's nested `make install` in its own package
  directory; without it, an attempt with Mopsa 1.1 selected the enclosing
  Frama-C workspace and failed. Scope the variable to that opam command.
- **`gcc-multilib`** provides the libc headers outside the multiarch
  directory. Without it, `tests/fc_script/make-machdep.t` fails: `clang
  --target=x86_64` does not find `sys/types.h`.
- **PyYAML** is required by `share/machdeps/make_machdep/make_machdep.py`. With
  the venv on `PATH`, its Python is the one the tests use.
- **Apron** enables additional Eva domains, **ZeroMQ** the server, **Mopsa**
  the integration-test tools (it needs the LLVM development packages).
  `headache`, `camomile` and `ocp-indent` support the developer checks.
  Alt-Ergo 2.6.4 matches the development dependency in `opam`.

## Repairing the Dune version

```sh
DUNE_ROOT=. opam install --switch=. dune.3.21.1 -y --jobs=8
opam pin add --switch=. dune 3.21.1 --no-action -y
```

The first command recompiles the packages that depend on Dune.

## Limits of this platform

On Ubuntu 24.04 the configuration probe reports Eva and syntax test
prerequisites as missing although the executables are present: Graphviz 2.43
accepts `dot -V` where the probe runs `dot --version`, and GCC 13.3 lacks
`-std=c2y`. Generate the regression rules with
`dune exec -- frama-c-ptests -never-disabled tests plugins/*/tests` and judge
by the test outcomes, not by the configuration summary. This does not enable
native Dune or cram tests that are disabled by a condition.

## GitHub Actions runner

On pushes to `nyandrianinamamy/frama-c`, the Ubuntu 24.04 runner labelled
`frama-c-vm` runs the kernel native tests and default ptests. Two GitHub-hosted
jobs run the Eva configurations in parallel. Pull requests and manual
dispatches run all three jobs on GitHub-hosted runners. The VM checkout
starts clean for every job. Only the build of `@install` uses its persistent
Dune cache.

The VM uses an administrator-owned `/opt/frama-c-ci` toolchain. To provision
another runner with that label, install the system packages listed in the
[CI workflow](../../.github/workflows/ci.yml), create the directory for the
provisioning user, then run the following from a Frama-C checkout as that
user. The runner account needs read and execute access to the toolchain.

```sh
export OPAMROOT=/opt/frama-c-ci/opam-root OPAMSWITCH=ci OPAMJOBS=6 OPAMYES=true
opam init --bare --disable-sandboxing --no-setup
opam switch create ci ocaml-base-compiler.5.2.1
opam install dune.3.21.1
opam pin add dune 3.21.1 --no-action
opam install --deps-only --with-test .
opam install apron zmq ocp-indent.1.10.0 headache camomile
python3 -m venv /opt/frama-c-ci/venv
/opt/frama-c-ci/venv/bin/pip install check-jsonschema==0.39.0 PyYAML==6.0.3 \
  black==26.10.1 clang-format==21.1.8
```

When dependencies change, apply the corresponding install commands to this
switch and venv and update the hosted setup in the same workflow.
