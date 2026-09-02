#!/bin/sh
# SPDX-License-Identifier: MIT
#
#   ./run.sh            format, build, then start the REPL
#   ./run.sh --build    format and build only
#   ./run.sh --check    fail if any source is unformatted (for CI)
#   ./run.sh --clean    remove build/
#   echo "1 + 2 * 3" | ./run.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CORE="$ROOT/src/core"
OUT="$ROOT/build"
BIN="$OUT/tsafoshi"

have() { command -v "$1" >/dev/null 2>&1; }

PY=
for c in python3 python py; do
    have "$c" && { PY=$c; break; }
done

case "${1:-}" in
    --clean)
        rm -rf "$OUT"
        echo "cleaned"
        exit 0
        ;;
    --check)
        [ -n "$PY" ] || { echo "run.sh: --check needs python" >&2; exit 127; }
        exec "$PY" "$ROOT/tools/prettier.py" --check "$ROOT/src"
        ;;
esac

have nasm || {
    echo "run.sh: nasm not found (apt install nasm | dnf install nasm | pacman -S nasm)" >&2
    exit 127
}

LD=
for c in ld ld.lld lld; do
    have "$c" && { LD=$c; break; }
done
[ -n "$LD" ] || {
    echo "run.sh: no linker found (apt install binutils | dnf install binutils)" >&2
    exit 127
}

[ -n "$PY" ] && "$PY" "$ROOT/tools/prettier.py" -q "$ROOT/src"

mkdir -p "$OUT"
OBJS=""
for src in "$ROOT/src/main.asm" "$CORE"/*.asm "$ROOT/src/linux/input.asm"; do
    obj="$OUT/$(basename "$src" .asm).o"
    nasm -f elf64 -g -F dwarf -I "$CORE" "$src" -o "$obj"
    OBJS="$OBJS $obj"
done

# shellcheck disable=SC2086
"$LD" -o "$BIN" $OBJS
echo "built $BIN"

case "${1:-}" in
    --build) exit 0 ;;
esac
exec "$BIN"
