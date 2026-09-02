# Tsafoshi

**צָפוֹן** *(tsafon,* north*)* + **星** *(hoshi,* star*)* → **Tsafoshi**, the north star.

A **C99** interpreter written in x86-64 assembly. No compiler backend, no code
generation, no ABI to fight — C source goes in, behaviour comes out. The host
is hand-written assembly the whole way down.

This is stage 1.5. Right now it is a calculator that compiles to bytecode
and runs it on a virtual machine.

```
tsafoshi> 2 + 3 * 4
= 14
tsafoshi> mode ltr
mode: ltr
tsafoshi> 2 + 3 * 4
= 20
```

BODMAS by default, and the order is switchable — see [Order of
operations](#order-of-operations).

---

## What this is, and what it isn't

Tsafoshi is an **experiment**, not a drop-in C toolchain. It is a long-form
exercise in building a language runtime by hand, in assembly, one deliberate
stage at a time. The interesting part is the construction, not the product.

Concretely, that means:

- It implements a **subset** of C99, and will for a long time. See the stage
  table below for what exists today — right now it is a calculator.
- It is not a replacement for `gcc`, `clang` or `tcc`, and it is not trying to
  be. If you need to actually run C, use one of those.
- Nothing here is hardened. There is no fuzzing, no sanitizer coverage, and no
  security review. Do not point it at untrusted input.
- Interfaces between modules will change as the stages land.

If you want to read how a scanner, a parser and a runtime fit together with
nothing underneath them, this is for you. If you want to compile a project,
it is not.

### On AI assistance

Parts of this codebase were written with AI help. Being specific about what
that means, because "AI-assisted" covers a wide range:

- **Where it was used:** boilerplate and repetitive scaffolding (the platform
  I/O wrappers, the build scripts, `tools/prettier.py`), and working through
  specific well-scoped problems — SysV vs. Microsoft x64 calling convention
  details, the `INT64_MIN / -1` idiv trap, correct `INT64_MIN` formatting,
  buffered line reading that behaves the same on a pipe and a console.
- **Where it was not:** the project itself. The architecture, the module
  boundaries, the staging plan, and the decisions about what Tsafoshi is were
  not delegated. This was not handed to a model as "write me a C interpreter."

Everything in the tree has been assembled, linked and run on both targets, and
the behaviour in this README is copied from real output rather than described
from memory. That said — treat it as experimental code by an author using
assistance, not as reviewed, production-grade work.

## Status

| Stage | What it does | State |
|---|---|---|
| **0** | Tokenizer, recursive-descent parser, left-to-right evaluation, 64-bit signed ints | **done** |
| **1** | Precedence climbing, an AST, switchable evaluation order | **done** |
| **1.5** | Bytecode: compile the tree, then run it in a dispatch loop, plus a disassembler | **done** |
| 2 | Variables, assignment, `if` / `while`, the VM call stack | next |
| 3 | Functions, pointers, arrays, `struct` | |
| 4 | Native call bridge — `printf` starts working | |
| 5 | Preprocessor: `#include`, `#define`, `#if`, `__VA_ARGS__` | |
| 6 | The rest of C99 — VLAs, designated initializers, compound literals | |

## Target: C99

ISO/IEC 9899:1999. Old enough to be completely specified, settled and
understood; new enough that the language is pleasant to write. C89 costs too
much for no gain — declarations dragged to the top of every block, no `//`
comments, no `long long`. C11 and later add machinery (`_Generic`, atomics,
threads, `_Static_assert`) that is real work for a hosted interpreter and buys
this project nothing.

What choosing C99 specifically commits us to, beyond C89:

| | |
|---|---|
| `//` comments | lexer, stage 2 |
| Declarations anywhere in a block, and in `for` init | parser + scoping, stage 2 |
| `long long`, `_Bool`, `<stdbool.h>`, `<stdint.h>` | type system, stage 3 |
| Designated initializers, compound literals | stage 6 |
| Flexible array members | stage 6 |
| Variadic macros (`__VA_ARGS__`) | preprocessor, stage 5 |
| No implicit `int`, no implicit function declarations | diagnostics, throughout |
| **Variable length arrays** | the runtime stack design, stage 6 |

VLAs are the one that genuinely shapes the architecture. They were made
mandatory in C99 (and optional again in C11), and they mean a stack frame's
size is not known until run time — so the managed C stack needs a real frame
pointer and runtime-computed offsets rather than a fixed layout baked in by
the front end. That constraint gets designed in at stage 2, not retrofitted at
stage 6.

**Deliberately out of scope**, C99 or not: `_Complex` and `_Imaginary` (C11
made them optional for good reason), and `<threads.h>`-style concurrency.
Floating point is deferred until the integer language is complete, not
abandoned.

## The 64-bit cell rule

**Every slot on the evaluation stack is 64 bits, unless a specific opcode says
otherwise.** One width, everywhere, for every C type. `CELL equ 8` in
`src/core/tsafoshi.inc` is the single place that number lives.

This is the standing simplification the rest of the runtime is built on. It
costs memory and buys a great deal: no per-type stack layout, no slot-size
bookkeeping in the parser, and one `push` / `pop` shape for everything. It is
also roughly what the SysV ABI already does when it promotes arguments into
8-byte slots, so it is a shortcut with good company.

One distinction has to hold, though, or `sizeof` and pointer arithmetic come
apart:

|  | Width |
|---|---|
| A slot on the evaluation stack | always `CELL` (8 bytes) |
| A C object in memory — struct field, array element, global | its real C width |

So `sizeof(int)` is 4 and `int a[10]` is 40 bytes, even though loading `a[3]`
puts it in a 64-bit cell. Typed opcodes bridge the two: `LOAD_I32` sign-extends
4 bytes of memory into a full cell, `STORE_I32` truncates a cell back down to 4
bytes, and `ADD_I32` wraps its result at 32 bits before leaving it in the
64-bit slot. Widening on the stack must never become widening in the semantics
— `INT_MAX + 1` still has to land on `INT_MIN`.

### Other standing assumptions

Recorded here rather than rediscovered later. All of these are conscious
shortcuts, and all of them are revisable:

- **Signed overflow wraps.** It is undefined behaviour in the standard; here it
  is two's complement, silently, because that is what the hardware does.
- **C pointers are real host addresses**, not offsets into a sandbox. No bounds
  checking. A bad pointer in interpreted code faults the interpreter.
- **One flat memory region** for globals, the managed C stack and the heap.
- **`char` is signed**, and 8 bits. Plain `int` is 32 bits, `long` and pointers
  are 64.
- **Little-endian x86-64 only.** Byte order is assumed, not abstracted.
- **No floating point yet.** Deferred until the integer language is complete.

## Build and run

Needs [NASM](https://www.nasm.us/) and a linker. There is no Makefile and no
CMake — the build is a file list and one link step.

**Linux**

```sh
./run.sh              # format, build, then start the REPL
./run.sh --build      # format and build only
./run.sh --check      # fail if any source is unformatted (CI)
./run.sh --clean      # rm -rf build/
echo "1 + 2 * 3" | ./run.sh
```

**Windows**

```bat
run.bat
run.bat --build
run.bat --check
run.bat --clean
```

`run.bat` assembles with NASM and links with whichever of `lld-link` (LLVM),
`link.exe` (MSVC), `gcc` (mingw-w64) or `GoLink` it finds first. The first
three also need `kernel32.lib` from the Windows SDK, which the script locates
automatically.

Both scripts run `tools/prettier.py` over `src/` before assembling, if Python
is available.

## Using it

```
tsafoshi> 100 - 20 - 5
= 75
tsafoshi> (2 + 3) * 4
= 20
tsafoshi> -7 % 3
= -1
tsafoshi> mode
mode: bodmas
  bodmas  brackets, then * / %, then + -
  ltr     one flat level, folded left to right
  rtl     one flat level, folded right to left
tsafoshi> 4 / 0
            ^
error: division by zero
tsafoshi> 2 +
            ^
error: expected a number or '('
tsafoshi> quit
```

Operators: `+ - * / %`, unary `-` and `+`, and parentheses. Values are 64-bit
signed and wrap silently on overflow.

| Command | Effect |
|---|---|
| `mode`, `mode <name>` | report or change the evaluation order |
| `engine`, `engine tree`, `engine bytecode` | which engine runs the expression |
| `dis` | toggle the bytecode listing |
| `quit`, `exit`, `q`, EOF | leave |

These are matched before the expression parser sees the line, so `mode`,
`engine` and `dis` are effectively reserved words. That is fine while the
language has no identifiers and will not be once stage 2 adds variables — the
plan is to move every command behind a `:` prefix at that point, in one go.

## Bytecode

The parser builds a tree, `compile.asm` flattens it to bytecode, and `vm.asm`
runs that in a dispatch loop. `dis` shows the middle step:

```
tsafoshi> dis
disassembly: on
tsafoshi> 2 + 3 * 4
    0000  push 2
    0009  push 3
    0018  push 4
    0027  mul
    0028  add
    0029  halt
= 14
```

A stack machine over 64-bit cells, one byte of opcode, and an operand only
where one is needed:

| Opcode | Operand | Effect |
|---|---|---|
| `halt` | | stop; the answer is on top of the stack |
| `push` | 8-byte immediate | push it |
| `add` `sub` `mul` `div` `mod` | `div` and `mod` take a 4-byte column | pop two, push the result |
| `neg` | | negate the top |

The binary opcodes are numbered in token order, so an operator token becomes
its opcode with a subtract and an add rather than a table lookup.

`div` and `mod` are the only operations that can fail, and by the time the VM
is running there is no tree left to ask where they came from — so those two
carry the column they were written at, and a division by zero still gets its
caret in the right place. Nothing else pays for that.

### Two engines, on purpose

The tree walker from stage 1 is still there, and `engine tree` switches back to
it. It is not a fallback. It is an oracle: two independent implementations of
the same semantics, which must agree on every input, so a bug in either one
shows up as a disagreement rather than as a wrong answer nobody notices.

Both call the same routines in `op.asm`, so they cannot disagree about what
`%` means — only about order, operand plumbing, and the encoding. Those are
exactly the things a new execution layer gets wrong.

## Order of operations

The default is **BODMAS**: brackets first, then `* / %`, then `+ -`, with
equal-strength operators folded left. That is also exactly what C99 specifies
for these operators, so the default needs no apology and will not have to
change when the rest of the language arrives.

The order is a runtime setting rather than a fact baked into the parser:

| `mode` | Rule | `2 + 3 * 4` | `2 - 3 - 4` |
|---|---|---|---|
| `bodmas` | brackets, then `* / %`, then `+ -`; folds left | `14` | `-5` |
| `ltr` | one flat level, folded left to right | `20` | `-5` |
| `rtl` | one flat level, folded right to left | `14` | `3` |

`ltr` is the stage-0 behaviour kept as a mode: no precedence at all, so
parentheses are the only way to regroup. `rtl` is the APL rule — still no
precedence, but a run of equal operators folds from the right, which is why
`2 - 3 - 4` becomes `2 - (3 - 4)`.

Parentheses win under every mode. They are structural, handled in
`parse_primary`, and never consult the table.

### How the switch works

`parser.asm` asks `mode.asm` two questions and holds no opinion of its own:

```
mode_prec(kind)   ->  how tightly this operator binds, 0 if it is not one
mode_bump         ->  1 to fold left, 0 to fold right
```

Precedence climbing turns both into one loop. After reading an operator of
strength `q`, the parser parses the right operand with a floor of
`q + mode_bump`. With the bump at 1 an equally strong operator is refused on
the right, falls out to the loop, and folds leftward; with the bump at 0 it is
accepted and folds rightward. A mode is therefore a five-byte precedence row
plus that one flag, and the two flat modes are the same row with different
bumps.

Adding the rest of C99's binary operators means adding tokens and widening
those rows. The `PREC_*` ladder in `tsafoshi.inc` is already numbered for it:
shifts, comparisons, equality and the bitwise operators have their C99 levels
reserved at 5 through 8, so nothing that already exists gets renumbered.

## Layout

```
src/
  main.asm              _start -> repl_main. The entry point, and nothing else.
  core/                 platform-independent, assembled once
    tsafoshi.inc        shared constants and token kinds
    repl.asm            the read-eval-print loop
    readline.asm        buffered line input
    lexer.asm           source text -> tokens
    parser.asm          tokens -> a syntax tree (structure only)
    ast.asm             node storage: one arena, reset per line
    eval.asm            tree -> value directly (the oracle engine)
    compile.asm         tree -> bytecode
    code.asm            the code buffer, reset per line
    vm.asm              the dispatch loop and its operand stack
    disasm.asm          bytecode -> a listing
    exec.asm            which engine runs, and the commands that switch it
    op.asm              operator semantics (values)
    mode.asm            evaluation order, and the "mode" command
    error.asm           diagnostics and the caret
    format.asm          number formatting, output helpers
  linux/input.asm       I/O primitives, Linux syscalls
  windows/input.asm     I/O primitives, Windows kernel32
tools/prettier.py       source layout normalizer
```

Start reading at `src/main.asm`. It is five instructions: align the stack, cut
the frame chain, call `repl_main`. Both platforms share it — Linux `ld` picks
`_start` up by default and the Windows linkers are passed `/entry:_start`, so
there is no conditional assembly anywhere in the tree.

Each `.asm` is its own translation unit; they are assembled separately and
linked. Cross-module symbols are explicit `global` / `extern`, so the
dependency graph is visible at the top of every file.

The build is `src/main.asm` plus `src/core/*.asm` plus exactly one
`src/<platform>/input.asm`. The core never names a platform.

### The module seams

| Seam | Interface |
|---|---|
| lexer → parser | `lex_init`, `lex_next`, and one token of lookahead in `tok_kind` / `tok_val` / `tok_pos` |
| parser → ast | `ast_num` / `ast_unary` / `ast_binary`, each returning a node or zero |
| parser → mode | `mode_prec(kind)` and `mode_bump` — the parser never hardcodes an order |
| tree → engine | `exec_run(root)`, which is either `ast_eval` or `code_compile` then `vm_run` |
| engine → op | `op_apply(lhs, rhs, kind, pos)` and the `op_*` routines — the engine decides order, `op.asm` produces every value |
| compiler → vm | the code buffer in `code.asm`; neither module owns the memory, so `disasm.asm` reads it without either knowing |
| anything → error | `err_expected` / `err_unclosed` / `err_divzero` / `err_trailing` / `err_toobig`, each taking a position |
| core → platform | the four `sys_*` routines below |

The tree is the seam that matters. The parser builds nodes and never computes
a value; a consumer walks nodes and never looks at a token. That is what made
the bytecode compiler a purely additive change — it is a second consumer of
the same tree, and not one line of the lexer or the parser moved to get it.

`op_apply`, `ast_eval`, `emit_node` and the VM's inner loop all dispatch
through jump tables, indexed by token kind, node kind, node kind and opcode
respectively.

Nodes come out of a bump-allocated arena that the REPL resets once per line,
so a tree costs one pointer bump per node and nothing at all to free. Running
out raises `expression too complex`; with `AST_CAP` at 4096 nodes and
`LINE_CAP` at 1024 bytes a single line cannot actually reach it, so it is a
guard for the multi-line input that arrives with the preprocessor rather than
a limit you can hit today.

### The platform contract

Any new `input.asm` provides exactly four routines. The entry point is not one
of them — `src/main.asm` is shared:

| | |
|---|---|
| `sys_write_stdout` | `rsi` = buffer, `rdx` = length |
| `sys_write_stderr` | `rsi` = buffer, `rdx` = length |
| `sys_read_stdin` | `rsi` = buffer, `rdx` = capacity → `rax` = bytes, `<= 0` at EOF |
| `sys_exit` | `edi` = status, does not return |

They may clobber the caller-saved registers freely. `rbx` and `r12`–`r15` must
survive — the core keeps live state there across every call.

### Why Windows does not use raw syscalls

Linux system call numbers are a stable public ABI, so `src/linux/input.asm`
issues `syscall` directly and links against nothing. Windows has an equivalent
gate, but its service numbers are private and get renumbered between builds;
hardcoding them buys you a binary that breaks on the next update. The stable
public boundary on Windows is kernel32, so that is what `src/windows/input.asm`
calls.

What genuinely differs between the two files is the **calling convention**:

| | System V (Linux) | Microsoft x64 (Windows) |
|---|---|---|
| Integer args | `rdi rsi rdx rcx r8 r9` | `rcx rdx r8 r9`, rest on the stack |
| Shadow space | none | 32 bytes, always, even for one argument |
| Kernel arg 4 | `r10` (not `rcx`) | n/a |
| `rdi` / `rsi` | caller-saved | **callee-saved** |
| Syscall clobbers | `rcx`, `r11` | n/a |

Both wrappers align the stack to 16 bytes at every `call` and build their own
frames, so the core stays convention-agnostic.

## Formatting

`tools/prettier.py` normalizes NASM layout: labels at column 0, code indented
four, mnemonics in a fixed field, comments aligned, `%` directives flush left.
It is quote-aware and idempotent.

```sh
python tools/prettier.py            # format src/ in place
python tools/prettier.py --check    # exit 1 if anything would change
```

The run scripts invoke it before every build, so formatting never drifts.

## Porting

ARM64 and 32-bit x86 are not here and are not planned. The design makes them
straightforward forks: reimplement the four `sys_*` routines, keep the register
contract, and `src/core/` is untouched.

## Design notes

**Why an interpreter and not a compiler.** Writing the host in assembly means
every line of code generation would be assembly emitting assembly, plus
register allocation and full ABI conformance for every call. An interpreter
trades all of that for a dispatch loop — which is the one structure assembly is
genuinely good at.

**Where the real difficulty lives.** Not in the evaluator. The bulk of a C
interpreter is the preprocessor and the parser, both of which are string
manipulation, which is exactly what assembly makes tedious. Expect roughly two
thirds of the eventual line count to be front end and support code.

**The plan for values.** From stage 3 onward, C programs will do pointer
arithmetic and `memcpy` over structs, so values cannot be boxed. The runtime
gets one flat `mmap` / `VirtualAlloc` region holding globals, a managed C stack
and a heap, with C pointers as real host addresses. Types get resolved in the
front end and baked into typed opcodes (`ADD_I32`, `LOAD_I8_SX`, pointer
arithmetic with the scale as an immediate), so the interpreter never inspects a
type at runtime.

Note the seam C99 forces here: *types* are always static, but with VLAs a
*size* need not be. `sizeof` on a VLA is an expression evaluated at run time,
so the scale on a pointer-arithmetic opcode cannot always be an immediate —
some of them take it from the stack instead. That is a small extension to the
opcode set, but only if the frame layout allowed for it from the start.

**Why the order is switchable.** Precedence lives in a table because it was
going to have to anyway — C99 has more than a dozen binary levels, and
encoding those as control flow means a dozen nested rules to write and
re-read. Once the table exists, an alternate convention costs one more row.
Having three of them keeps the parser honest: no rule may assume a fixed
order, because the order is not known until run time.

**Why bytecode at all, this early.** A tree walker would carry the language a
long way, but every future feature is easier against a linear instruction
stream: jumps for `if` and `while` are branches to an offset rather than
another node type, a call stack has somewhere to live, and the interpreter's
hot loop stops being recursive descent over pointers. Retrofitting that after
control flow exists means rewriting control flow. Doing it while the language
is five operators means the whole change is three new files and no edits to
the front end.

**Assembler.** NASM. `%include`, `default rel` and the section syntax are
NASM-isms; FASM will build this with some edits.

## License

MIT — see [LICENSE](LICENSE). Every source file carries an SPDX identifier.

Copyright (c) 2026 Debaditya Malakar <debadityamalakar@gmail.com>.
