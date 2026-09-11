# One entry point for the commands that already exist. The scripts stay
# authoritative — these targets only sequence them, so there is a single place
# to look and a single command to remember.
#
#   make verify       app, shader and window invariants (needs a certificate)
#   make verify-release   the artifacts `make release` produced
#   make release      full local dry run; PUBLISH=1 to create the GitHub release
#
# CI does not use `verify`: the signed build needs a Developer ID identity, and
# the capture check needs a logged-in desktop. Its workflow stays as it is.
SHELL := /bin/zsh
.PHONY: build verify verify-release release

build:
	./scripts/build.sh --signed

verify: build
	./scripts/verify.sh
	./scripts/verify-capture.sh

verify-release:
	./scripts/verify-release.sh

release:
	./scripts/release.sh $(if $(PUBLISH),--publish,)
