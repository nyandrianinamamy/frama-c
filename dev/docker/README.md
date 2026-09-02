# Frama-C Docker images

Frama-C Docker images are currently available on three flavors:
- A Debian-based image (default);
- A Fedora-based image;
- An Alpine-based image.

The exact version of the base Docker image is defined in the Makefile.
These images are based on opam's Docker images.

The user is `opam` and it has sudo rights.

Frama-C dependencies are installed by opam.

There are 2 main images, each with 3 variants:

- `dev` image: based on the public Frama-C git repository;
- `custom` image: based on a custom .tar.gz archive put in this directory.
  Note: it _must_ be named `frama-c-<something>.tar.gz`, where
  `<something>` may be a version number, codename, etc.
  It _must_ be put in this directory.

## Built images

The `dev` images are tagged with their default names in the Docker Hub,
e.g. `framac/frama-c:dev`.

The `custom` images are tagged with prefix `frama-c-custom`, since they are
intended for local usage.
