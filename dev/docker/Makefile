##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

.ONESHELL:
.PHONY: dev* custom* help push

help:
	@echo "Available targets are:"
	echo "- dev: public Git development version"
	echo "- custom: version based on a frama-c-*.tar.gz archive"
	echo "  (custom targets require FRAMAC_ARCHIVE to be set)"
	echo ""
	echo "Targets for users with write access to the framac Docker Hub:"
	echo "- push TAG=<tag1> AS=<tag2>: perform a docker push with image"
	echo "  <tag1> sent as <tag2>. Usage example:"
	echo "  make push TAG=framac/frama-c:dev AS=framac/frama-c:dev"
	echo ""

DEPS=../../opam Dockerfile $(wildcard *.sh)

BUILD_ARGS += --build-arg=OPAM=2.4

dev: $(DEPS)
	docker build . -t framac/frama-c:$@ $(BUILD_ARGS) --target frama-c

ifeq ($(FRAMAC_ARCHIVE),)
custom:
	@echo "error: run '$(MAKE) $@ FRAMAC_ARCHIVE=frama-c-<version>.tar.gz',"
	echo "       where frama-c-<version>.tar.gz is the name of the archive."
	echo "Note: the archive must be in the current directory and be named as"
	echo "      'frama-c-<version>.tar.gz' (where <version> is at your choice)."
	exit 1
else
BUILD_ARGS += --build-arg=from_archive=$(FRAMAC_ARCHIVE)

custom: $(DEPS)
	docker build . -t frama-c-$@ $(BUILD_ARGS) --target frama-c

endif

# check if either TAG or AS are empty
ifeq ($(TAG)$(AS),$(AS)$(TAG))
push:
	@echo "error: run '$(MAKE) $@ TAG=<orig> AS=<new>'"
	echo "        where <tag> is the current tag of the image to be pushed,"
	echo "        and <new> is the name used in the Docker Hub"
	echo "        e.g. framac/frama-c:dev"
	echo "(if you supplied identical tags, just run 'docker push $(TAG)')"
	exit 1
else
push:
	docker tag $(TAG) $(AS)
	docker push $(AS)
endif
