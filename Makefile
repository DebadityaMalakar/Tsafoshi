# SPDX-License-Identifier: MIT
#
# Tsafoshi. Two targets, one source tree, and one file list.
#
#   make            format, build, then start a session
#   make build      format and build only
#   make check      fail if any source is unformatted (for CI)
#   make run        build, then run FILE=... with ARGS=...
#   make examples   build, then run every example
#   make test       build both engines' answers to the corpus and diff them
#   make clean      remove build/
#
# The only thing that varies by platform is three lines: the object format, the
# link step, and which of src/linux and src/windows joins the build. Everything
# else is shared, because the interpreter is -- there is no conditional
# assembly anywhere in the tree and this is the file that makes that possible.
#
# Detection is by uname, with the Windows shells that do not have one falling
# back to the OS variable they all set. Building for Windows from WSL or MSYS
# is "make PLATFORM=windows"; the detection is a default, not a decision.

ROOT     := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SRC      := $(ROOT)src
CORE     := $(SRC)/core
OUT      := $(ROOT)build

UNAME    := $(shell uname -s 2>/dev/null)
ifeq ($(UNAME),)
    PLATFORM ?= windows
else ifneq (,$(findstring MINGW,$(UNAME)))
    PLATFORM ?= windows
else ifneq (,$(findstring MSYS,$(UNAME)))
    PLATFORM ?= windows
else ifneq (,$(findstring CYGWIN,$(UNAME)))
    PLATFORM ?= windows
else
    PLATFORM ?= linux
endif

NASM     ?= nasm
# Not "the first one on PATH": Windows ships a python.exe that exists only to
# advertise the store, so the test is whether it runs rather than whether it is
# there. Without one the prettier is skipped and the build still works.
PYTHON   ?= $(shell for p in python3 python py; do if "$$p" -c pass >/dev/null 2>&1; then echo "$$p"; break; fi; done)

ifeq ($(PLATFORM),windows)
    FORMAT  := win64
    BIN     := $(OUT)/tsafoshi.exe
    DBGFLAG := -g
else
    FORMAT  := elf64
    BIN     := $(OUT)/tsafoshi
    DBGFLAG := -g -F dwarf
endif

# Objects live under the platform they were assembled for, because the two
# targets share every filename and nothing else: a win64 main.o and an elf64
# main.o cannot be told apart by a timestamp, and switching targets in the same
# tree would otherwise link yesterday's format.
OBJDIR   := $(OUT)/$(PLATFORM)
SOURCES  := $(SRC)/main.asm $(wildcard $(CORE)/*.asm) $(wildcard $(SRC)/$(PLATFORM)/*.asm)
OBJECTS  := $(patsubst %.asm,$(OBJDIR)/%.o,$(notdir $(SOURCES)))

vpath %.asm $(SRC) $(CORE) $(SRC)/$(PLATFORM)

.PHONY: all build run check examples test clean help

all: build
	@$(BIN)

build: $(BIN)

# The linker is whichever one is installed. On Linux that is ld or lld; on
# Windows the choice is wider and every one of them needs kernel32, which is
# the one library a program with no libc still cannot do without.
#
# lld-link's options are spelled with a dash rather than a slash, which it
# accepts and which matters: run from Git Bash or MSYS, "/nologo" is rewritten
# into a path on the way to the process and the linker is handed a filename it
# has never heard of.
$(BIN): $(OBJECTS)
	@mkdir -p $(OUT)
ifeq ($(PLATFORM),windows)
	@K32=$$(ls -d "/c/Program Files (x86)/Windows Kits/10/Lib"/*/um/x64/kernel32.Lib 2>/dev/null | tail -1); \
	if command -v lld-link >/dev/null 2>&1 && [ -n "$$K32" ]; then \
	    lld-link -nologo -subsystem:console -entry:_start -nodefaultlib $(OBJECTS) "$$K32" -out:$(BIN); \
	elif command -v gcc >/dev/null 2>&1; then \
	    gcc -nostdlib -Wl,-e,_start -o $(BIN) $(OBJECTS) -lkernel32; \
	else \
	    echo "make: no usable Windows linker (lld-link with the SDK, or gcc)"; exit 127; \
	fi
else
	@LD=$$(command -v ld || command -v ld.lld); \
	if [ -z "$$LD" ]; then echo "make: no linker found (ld or ld.lld)"; exit 127; fi; \
	$$LD -o $(BIN) $(OBJECTS)
endif
	@echo "built $(BIN)"

# The prettier runs before assembly rather than as a separate step, so the tree
# is never committed in a shape it was not formatted in.
$(OBJDIR)/%.o: %.asm | $(OBJDIR)
	@if [ -n "$(PYTHON)" ]; then $(PYTHON) $(ROOT)tools/prettier.py -q $<; fi
	@$(NASM) -f $(FORMAT) $(DBGFLAG) -I $(CORE) $< -o $@

$(OBJDIR):
	@mkdir -p $(OBJDIR)

run: build
	@$(BIN) $(FILE) $(ARGS)

check:
	@if [ -z "$(PYTHON)" ]; then echo "make check: needs python"; exit 127; fi
	@$(PYTHON) $(ROOT)tools/prettier.py --check $(SRC)

examples: build
	@for f in $(ROOT)examples/*.c; do \
	    echo "== $$f"; $(BIN) "$$f" || echo "  exit $$?"; \
	done

# The two engines are each other's oracle, so the test is that they agree --
# not that either matches a recorded answer.
test: build
	@$(BIN) -i --engine bytecode < $(ROOT)tests/corpus.txt > $(OUT)/bytecode.txt 2>&1
	@$(BIN) -i --engine tree     < $(ROOT)tests/corpus.txt > $(OUT)/tree.txt 2>&1
	@if diff -u $(OUT)/bytecode.txt $(OUT)/tree.txt; then \
	    echo "the engines agree on $$(grep -c . $(ROOT)tests/corpus.txt) lines"; \
	else \
	    echo "the engines disagree, which means one of them has a bug"; exit 1; \
	fi

clean:
	@rm -rf $(OUT)
	@echo cleaned

help:
	@echo "make            format, build, then start a session"
	@echo "make build      format and build only"
	@echo "make check      fail if any source is unformatted"
	@echo "make run FILE=examples/gcd.c ARGS='a b'"
	@echo "make examples   run every example"
	@echo "make test       diff the two engines over tests/corpus.txt"
	@echo "make clean      remove build/"
	@echo
	@echo "PLATFORM=$(PLATFORM) (override with PLATFORM=linux or PLATFORM=windows)"
