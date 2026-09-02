#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Normalize NASM source layout. Run by run.sh / run.bat before assembling.

    python tools/prettier.py            format src/ in place
    python tools/prettier.py --check    exit 1 if anything would change
    python tools/prettier.py FILE...    operate on specific files

Layout produced:

    label:
        mnemonic operands                   ; comment

Labels sit at column 0, code is indented, mnemonics are padded to a fixed
field, comments align. Preprocessor lines (%...) stay at column 0. A label
sharing a line with an instruction is split onto its own line. The pass is
idempotent: formatting formatted output changes nothing.
"""

import argparse
import pathlib
import re
import sys

INDENT = 4       # code indent
MNEMONIC = 8     # mnemonic field width, so operands land at INDENT + MNEMONIC
COMMENT = 40     # column trailing comments start at
TABSTOP = 8

SUFFIXES = (".asm", ".inc")

LABEL = re.compile(r"^([.$]?[A-Za-z_?][A-Za-z0-9_$#@~.?]*)\s*:\s*")
BARE_LABEL = re.compile(r"^([.$]?[A-Za-z_?][A-Za-z0-9_$#@~.?]*)\s+equ\s+(.*)$", re.I)


def split_comment(line):
    """Return (code, comment) splitting at the first ';' outside a quote."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'`":
            quote = ch
        elif ch == ";":
            return line[:i].rstrip(), line[i + 1:].strip()
    return line.rstrip(), None


def squeeze(text):
    """Collapse whitespace runs outside quotes; force exactly ', ' after commas.

    Single characters only ever enter `out`, so the trailing-space pops below
    stay correct and the pass is idempotent.
    """
    out, quote, i = [], None, 0
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            i += 1
        elif ch in "\"'`":
            quote = ch
            out.append(ch)
            i += 1
        elif ch.isspace():
            while i < len(text) and text[i].isspace():
                i += 1
            out.append(" ")
        elif ch == ",":
            while out and out[-1] == " ":
                out.pop()
            out.append(",")
            out.append(" ")
            i += 1
            while i < len(text) and text[i].isspace():
                i += 1
        else:
            out.append(ch)
            i += 1
    return "".join(out).strip()


def attach(code, comment):
    if comment is None:
        return code.rstrip()
    if not code:
        return f"; {comment}"
    pad = max(COMMENT - len(code), 1)
    return f"{code}{' ' * pad}; {comment}"


def render_code(code):
    """One statement (no label, no comment) -> indented, aligned text."""
    code = squeeze(code)
    if not code:
        return ""
    if code.startswith("%"):
        return code
    parts = code.split(" ", 1)
    mnemonic = parts[0]
    rest = parts[1] if len(parts) > 1 else ""
    if not rest:
        return " " * INDENT + mnemonic
    pad = max(MNEMONIC - len(mnemonic), 1)
    return " " * INDENT + mnemonic + " " * pad + rest


def format_line(raw):
    """-> list of output lines."""
    line = raw.replace("\t", " " * TABSTOP).rstrip()
    if not line.strip():
        return [""]

    code, comment = split_comment(line)

    if not code:
        # Comment-only: column 0 if it was flush left, otherwise indented.
        prefix = "" if raw[:1] not in " \t" else " " * INDENT
        return [f"{prefix}; {comment}".rstrip()]

    if code.lstrip().startswith("%"):
        return [attach(squeeze(code.lstrip()), comment)]

    stripped = code.lstrip()

    # NAME equ VALUE -- a definition, not a label plus a statement.
    m = BARE_LABEL.match(stripped)
    if m:
        name, value = m.group(1), squeeze(m.group(2))
        pad = max(COMMENT // 2 - len(name), 1)
        return [attach(f"{name}{' ' * pad}equ {value}", comment)]

    m = LABEL.match(stripped)
    if m:
        label = f"{m.group(1)}:"
        rest = stripped[m.end():]
        if not rest:
            return [attach(label, comment)]
        return [label, attach(render_code(rest), comment)]

    return [attach(render_code(stripped), comment)]


def format_text(text):
    out = []
    for raw in text.splitlines():
        out.extend(format_line(raw))
    while out and not out[-1]:
        out.pop()
    return "\n".join(out) + "\n"


def targets(paths):
    for p in paths:
        p = pathlib.Path(p)
        if p.is_dir():
            yield from sorted(f for f in p.rglob("*") if f.suffix in SUFFIXES)
        elif p.suffix in SUFFIXES:
            yield p


def main():
    ap = argparse.ArgumentParser(description="Normalize NASM source layout.")
    ap.add_argument("paths", nargs="*", default=["src"])
    ap.add_argument("--check", action="store_true",
                    help="report files needing changes; do not write")
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args()

    dirty = []
    for path in targets(args.paths or ["src"]):
        original = path.read_text(encoding="utf-8")
        formatted = format_text(original)
        if formatted == original:
            continue
        dirty.append(path)
        if not args.check:
            path.write_text(formatted, encoding="utf-8", newline="\n")

    if args.check and dirty:
        for p in dirty:
            print(f"would reformat {p}")
        return 1
    if dirty and not args.quiet:
        for p in dirty:
            print(f"formatted {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
