# Inspired by https://github.com/Frederic-Boulanger-UPS/docker-framac and
# https://gitlab.inria.fr/why3/why3/-/blob/master/misc/Dockerfile.deploy

# DISTRO must be passed via --build-arg (see Makefile)
ARG DISTRO
ARG OCAML_VERSION_SHORT

# Stage 1: install dependencies
FROM ocaml/opam:debian-ocaml-5.5 AS base

ARG OPAM

RUN sudo ln -f /usr/bin/opam-${OPAM} /usr/bin/opam && opam init --reinit -ni

# Stage 2: install Frama-C itself

FROM base AS frama-c

## from_archive: if "git", clone from public Git; if prefixed with http,
## wget it; otherwise, use the given archive name.
## Note: the archive must contain a root directory
## starting with 'frama-c'
ARG from_archive=git

## The following line copies a frama-c archive if it exists, else nothing
COPY --chown=opam:opam README.md frama-c-*.tar.gz /frama-c/

RUN \
if [ "${from_archive}" != "git" ]; then \
  (cd /frama-c && \
    case "${from_archive}" in \
    "http"*) wget "${from_archive}" ;; \
          *) ;; \
    esac && \
    tar xvf "${from_archive##*/}" --strip 1 && \
    rm -f frama-c-*.tar.gz) \
; else \
  (cd /frama-c && rm -f * && git clone --depth 1 https://git.frama-c.com/pub/frama-c.git .) \
; fi

RUN cd /frama-c && opam pin add -k path . --confirm-level=unsafe-yes

## Run quick sanity checks
RUN \
eval $(opam env) && \
printf "int g;\n//@assigns g;\nvoid f(){g = 1;}\nint main() {f(); return g;}" > /tmp/simple.c && \
frama-c -eva -wp -report /tmp/simple.c && \
rm -f /tmp/simple.c && \
echo "int main() { /*@ assert 1 + 2 == 2; */ return 0; }" > /tmp/test-eacsl.c && \
(cd /tmp && e-acsl-gcc -c test-eacsl.c && \
./a.out.e-acsl 2>&1 | grep -q "Assertion failed" && \
rm -f ./a.out* test-eacsl.c)

## Cleanup
RUN \
  eval $(opam env) && \
  opam clean --yes --switch-cleanup && \
  rm -rf /home/opam/opam-repository

# Stage 5 (optional): tests

FROM frama-c AS tests

## Run standard Frama-C tests
RUN eval $(opam env) && cd /frama-c && make run-ptests && dune build @ptests_config

## Run an extra test for WP with provers
RUN eval $(opam env) && cd /frama-c/ && cd plugins/wp/tests/ && frama-c -wp wp_gallery/binary-multiplication-without-overflow.c -wp-prover alt-ergo
