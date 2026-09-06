#!/bin/sh
# SPDX-License-Identifier: MIT
#
# A shim. The build is the Makefile; this is here because "./run.sh" is what
# the first two stages of this project were run with and muscle memory is
# worth a five-line file.
#
#   ./run.sh              build, then start a session
#   ./run.sh --build      build only
#   ./run.sh --check      fail if any source is unformatted
#   ./run.sh --clean      remove build/
#   ./run.sh anything.c   build, then run that
set -e
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

case "${1:-}" in
    --build) exec make -C "$ROOT" build ;;
    --check) exec make -C "$ROOT" check ;;
    --clean) exec make -C "$ROOT" clean ;;
esac

make -C "$ROOT" build >/dev/null
exec "$ROOT/build/tsafoshi" "$@"
