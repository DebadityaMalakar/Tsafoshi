# Tsafoshi

**צָפוֹן** *(tsafon,* north*)* + **星** *(hoshi,* star*)* → **Tsafoshi**, the north star.

A **C99** interpreter written in x86-64 assembly. No compiler backend, no code
generation, no ABI to fight — C source goes in, behaviour comes out. The host
is hand-written assembly the whole way down.

This is stage 2.3. It compiles to bytecode, runs it on a virtual machine, and
has variables, control flow, lexical scope, and now functions with a real call
stack — so it will run a C file, starting at `main`, and exit with what `main`
returned.

```sh
$ cat examples/gcd.c
#include <stdio.h>

int gcd(int a, int b)
{
    while (b != 0) {
        int t = b;
        b = a % b;
        a = t;
    }
    return a;
}

int main(void)
{
    printf("gcd(1071, 462) = %d\n", gcd(1071, 462));
    return 0;
}

$ ./run.sh --build && ./build/tsafoshi examples/gcd.c
gcd(1071, 462) = 21
```

Or interactively:

```
tsafoshi> int fib(int n) {
     ...>     if (n < 2) return n;
     ...>     return fib(n - 1) + fib(n - 2);
     ...> }
tsafoshi> fib(20)
= 6765
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
  table below for what exists today — right now it is expressions, variables
  and one builtin function.
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
| **2.1** | Variables, assignment, statements, `printf` | **done** |
| **2.2** | `if` / `while` / `for` / `do`, jumps, blocks and scope | **done** |
| **2.3** | The VM call stack, user-defined functions, running a `.c` file | **done** |
| **3.1** | A proper command line: flags, `argv`, exit status, a REPL that knows it is one | **done** |
| **3.2** | Types: `char`, `short`, `int`, `long`, `_Bool`, `signed` / `unsigned`, `sizeof`, casts, conversions, typed opcodes | **done** |
| 3.3 | Pointers and arrays: `&`, `*`, subscripting, pointer arithmetic, real strings | next |
| 3.4 | `struct` and `union`, member access, passing and returning them | |
| 3.5 | `float` and `double`: SSE, literals, conversions, `%f` | |
| 4.1 | The library bridge: one signature, a lazily bound table, `<stdarg.h>` | |
| 4.2 | `<string.h>`, `<ctype.h>` — bytes and characters | |
| 4.3 | `<stdlib.h>` — an allocator, conversions, `qsort`, `rand` | |
| 4.4 | `<stdio.h>` in full — `FILE`, the `f*` family, `sprintf`, input | |
| 4.5 | `<math.h>` — needs 3.5 | |
| 4.6 | `<stddef.h>` `<stdint.h>` `<limits.h>` `<float.h>` `<stdbool.h>` `<inttypes.h>` — types and constants | |
| 4.7 | `<time.h>` `<assert.h>` `<errno.h>` `<signal.h>` `<setjmp.h>` | |
| 5 | Preprocessor: `#include` resolving to `.c`, `#define`, `#if`, `__VA_ARGS__` | |
| 6 | The rest of C99 — VLAs, designated initializers, compound literals | |
| 7 | The end game: a raylib port, and Tetris on top of it | |

### The standard library, and why it is seven stages

**There is no libc to bridge to.** The founding rule of this project is C
without using C, and linking glibc to get `strlen` would end it — so the
standard library is *written here*, in assembly, alongside everything else.
That is a correction to what this table used to say. A bridge to a real libc
would have been a smaller job and a different project.

They are **built in, and bound on use**. The whole library is one read-only
table in the binary: a module, a name, an arity, a signature, and the address
of a routine. Nothing is interned, allocated or wired at startup. The first
time a program *names* `strlen`, that one entry is bound — a name slot, a
builtin id, an arity the parser can check — and the other two hundred entries
cost exactly what they cost sitting in `.rodata`, which is nothing you can
measure. A program that never mentions `<math.h>` pays nothing for it, and
start-up stays what it is today: no allocation and no syscalls.

Which is also what keeps `#include` honest. Since stage 2.3 a `#include` line
has been accepted and ignored, because the library was already there; that
does not change when the library gets large. `#include <string.h>` remains a
statement of what you depend on rather than an instruction to go and get it,
and a program that forgets the line still works, exactly as it does now.

| Stage | | Wants |
|---|---|---|
| **4.1** | **The bridge.** One signature for every library routine, the lazy binding above, arity and type checking in the parser, and `<stdarg.h>` — variadics are a calling-convention question, so they belong with the convention. | 3.3 |
| **4.2** | **`<string.h>`, `<ctype.h>`.** `strlen` `strcpy` `strcmp` `strcat` `strchr` `strstr` `memcpy` `memmove` `memset` `memcmp`, and the twelve `is*` / `to*`. The pure ones: bytes in, bytes out, no allocation and no platform. | 3.3 |
| **4.3** | **`<stdlib.h>`.** `malloc` `free` `calloc` `realloc` against a real allocator, `atoi` `strtol` `strtod`, `abs` `labs` `div`, `rand` `srand`, `qsort` `bsearch`, `abort` `getenv`. The allocator grows the platform seam by one routine — `mmap` on Linux, `VirtualAlloc` on Windows — and is the first thing here that needs one. | 3.3 |
| **4.4** | **`<stdio.h>` in full.** What exists today is one `printf` writing to one descriptor. This is `FILE`, `fopen` `fclose` `fread` `fwrite` `fseek` `ftell` `feof`, `fprintf` `sprintf` `snprintf` `vsnprintf`, `puts` `putchar` `fgets` `getchar`, and the `scanf` family. `printf_run` already parses a format; it grows a destination. | 3.4 |
| **4.5** | **`<math.h>`.** `sqrt` `fabs` `floor` `ceil` `fmod` are single instructions. `sin` `cos` `tan` `atan2` `exp` `log` `pow` are not, and get the x87 transcendentals rather than polynomial approximations written from scratch — which is the one place this project takes the hardware's word for an answer. | 3.5 |
| **4.6** | **The type and limit headers.** `<stddef.h>` `<stdint.h>` `<limits.h>` `<float.h>` `<stdbool.h>` `<inttypes.h>`. Almost no code: `size_t`, `ptrdiff_t`, `intN_t`, `NULL`, `offsetof`, `bool` / `true` / `false`, and the `*_MAX` constants. The cheapest stage here and the one the most real source silently depends on. | 3.4 |
| **4.7** | **The rest of what programs include.** `<time.h>` (`time` `clock` `difftime` — and the platform's clock, which raylib will want), `<assert.h>`, `<errno.h>`, `<signal.h>`, `<setjmp.h>`. | 4.1 |

**Deliberately not planned**: `<complex.h>`, `<fenv.h>`, `<tgmath.h>`,
`<iso646.h>`, `<locale.h>`, `<wchar.h>` and `<wctype.h>`. Seven of C99's
twenty-four headers, all of them either already ruled out above or a wide
character model this interpreter has no business pretending to have.

**Why 3.5 exists.** `<math.h>` cannot be written for a language with no
floating-point type, so `float` and `double` had to land somewhere before 4.5
— and they are a language feature rather than a library one: SSE registers,
literals with a decimal point, the conversion rules extended, `%f` in
`printf`. Putting them in stage 3 with the rest of the type system is where
they belong; discovering that while splitting stage 4 is the useful part.

**What the end game actually needs.** raylib leans on 4.2, 4.3 and 4.5 hardest
— `Vector2` maths, allocation, and trigonometry — with 4.4 mostly for asset
loading and 4.7 for timing. That ordering is not an accident: the substages
are sorted by what a graphics library asks for first.

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
| `//` comments | lexer, **done** at stage 2.2 |
| Declarations anywhere in a block, and in `for` init | parser + scoping, **done** at stage 2.2 |
| `int main(void)` as the entry point of a file | **done** at stage 2.3 |
| `long long`, `_Bool` | type system, **done** at stage 3.2 |
| `<stdbool.h>`, `<stdint.h>`, `<inttypes.h>` | built in, stage 4.6 |
| Designated initializers, compound literals | stage 6 |
| Flexible array members | stage 6 |
| Variadic macros (`__VA_ARGS__`) | preprocessor, stage 5 |
| No implicit `int`, no implicit function declarations | diagnostics, throughout |
| **Variable length arrays** | the runtime stack design, stage 6 |

VLAs are the one that genuinely shapes the architecture. They were made
mandatory in C99 (and optional again in C11), and they mean a stack frame's
size is not known until run time — so the managed C stack needs a real frame
pointer and runtime-computed offsets rather than a fixed layout baked in by
the front end. That constraint gets designed in at stage 2.3, not retrofitted at
stage 6.

**Deliberately out of scope**, C99 or not: `_Complex` and `_Imaginary` (C11
made them optional for good reason), and `<threads.h>`-style concurrency.
Floating point is deferred until the integer language is complete, not
abandoned — it is stage 3.5, and `<math.h>` waits on it.

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

So `sizeof(int)` is 4 and `int a[10]` will be 40 bytes, even though loading
`a[3]` puts it in a 64-bit cell.

Stage 3.2 bridged the two, and did it with **one invariant rather than a family
of typed opcodes**:

> A cell always holds its type's value, extended to 64 bits — sign-extended
> when the type is signed, zero-extended when it is not.

Which means narrowing happens exactly once, at the moment a value is produced
or stored, and nothing downstream ever has to ask how wide a thing really is.
`char c = 300` stores 44 because a `conv` node sits in front of the store;
`c + 1` is 45 because what was loaded was already 44. `INT_MAX + 1` lands on
`INT_MIN` because the `add` is followed by a `conv int`, not because `add`
knows anything about ints.

That is why there is no `add_i32`. There is one `add`, and a `conv` after it
where the result is narrower than a cell. Seven opcodes did have to be doubled
— the ones where signedness genuinely changes the instruction — and nine did
not, which the tables in `op.asm` say out loud by repeating the same nine
entries twice.

### Other standing assumptions

Recorded here rather than rediscovered later. All of these are conscious
shortcuts, and all of them are revisable:

- **Signed overflow wraps.** It is undefined behaviour in the standard; here it
  is two's complement, silently, because that is what the hardware does.
- **C pointers are real host addresses**, not offsets into a sandbox. No bounds
  checking. A bad pointer in interpreted code faults the interpreter.
- **One flat memory region** for globals, the managed C stack and the heap.
- **`char` is signed**, and 8 bits. Plain `int` is 32 bits, `long` and pointers
  are 64. `long long` is accepted and is the same 8 bytes as `long`, which is a
  real C99 type this interpreter cannot tell apart from another one.
- **Duplicate type specifiers are not diagnosed.** `short short x` is accepted
  and means `short`. A repeated `long` does count, because `long long` has to.
- **Little-endian x86-64 only.** Byte order is assumed, not abstracted.
- **No floating point yet.** Deferred until the integer language is complete.

## Build and run

Needs [NASM](https://www.nasm.us/) and a linker. No CMake and no configure
step: the build is a file list, an object format and one link.

```sh
make                        # format, build, then start a session
make build                  # format and build only
make check                  # fail if any source is unformatted (CI)
make test                   # run both engines over the corpus and diff them
make examples               # run every example
make run FILE=examples/gcd.c ARGS="a b"
make clean
```

**Three lines vary by platform** — the object format, the link step, and which
of `src/linux` and `src/windows` joins the build. Everything else is shared,
because the interpreter is: there is no conditional assembly anywhere in the
tree, and the Makefile is what makes that possible rather than what works
around it.

The target is detected from `uname` and can be overridden, which is how you
cross-build from WSL:

```sh
make PLATFORM=windows       # win64 objects, lld-link, src/windows
make PLATFORM=linux         # elf64 objects, ld, src/linux
```

Objects live under `build/<platform>/`, because the two targets share every
filename and nothing else — a win64 `main.o` and an elf64 `main.o` cannot be
told apart by a timestamp, and switching targets in one tree would otherwise
link yesterday's format.

`make` needs a POSIX shell, which Linux, WSL, MSYS2 and Git Bash all have. The
one environment it cannot serve is native `cmd`, so **`run.bat` is still there
and still standalone**: it assembles with NASM and links with whichever of
`lld-link` (LLVM), `link.exe` (MSVC), `gcc` (mingw-w64) or `GoLink` it finds,
the first three also wanting `kernel32.lib` from the Windows SDK, which it
locates itself. `run.sh` is now a five-line shim over `make`.

Both routes run `tools/prettier.py` over the sources before assembling, so the
tree is never committed in a shape it was not formatted in.

`make test` is the one worth knowing about. There is no file of expected
answers: the two engines are each other's oracle, so the test is that the tree
walker and the bytecode VM produce **the same output** for every line of
`tests/corpus.txt`. The day they disagree, one of them has a bug and the diff
says where.

## Using it

```
tsafoshi> 100 - 20 - 5
= 75
tsafoshi> int n = 0;
tsafoshi> n = n + 1; n = n + 1;
tsafoshi> n
= 2
tsafoshi> printf("[%5d] [%-5d] [%05d]\n", 42, 42, -42)
[   42] [42   ] [-0042]
= 24
tsafoshi> :vars
  n = 2
tsafoshi> 4 / 0
            ^
error: division by zero
tsafoshi> 2 +
             ^
error: expected an expression
tsafoshi> :quit
```

A line is a sequence of statements, and a **bare expression at the end of one**
is the line's value — which is the only reason the prompt has anything to
echo. Put a `;` after it and it becomes a statement like any other, and
nothing is printed. That is exactly the C distinction between a statement and
the expression inside it, and the reason `n = n + 1;` prints nothing while `n`
prints `= 2`.

### Operators

The full C99 ladder below assignment, minus the ones that need types:

| Level | Operators | |
|---|---|---|
| 10 | `*` `/` `%` | |
| 9 | `+` `-` | |
| 8 | `<<` `>>` | `>>` is arithmetic on a signed left operand and logical on an unsigned one |
| 7 | `<` `>` `<=` `>=` | yield `1` or `0`, as C says |
| 6 | `==` `!=` | |
| 5 | `&` | |
| 4 | `^` | |
| 3 | `\|` | |
| 2 | `&&` | short-circuits |
| 1 | `\|\|` | short-circuits |

Prefix `-` `+` `!` `~`, parentheses, casts, and `sizeof`. Since stage 3.2 the
type of the operands decides which of two machine operations an operator
actually is — `/`, `%`, `>>` and the four inequalities all differ between
signed and unsigned — and the result wraps at the width of its own type rather
than at 64 bits. A shift count outside the width is undefined behaviour in C99;
here it is what the hardware does, which is to use the low six bits.

`&&` and `||` are the only two operators with no opcode behind them. Both
operands would have to be values before `op.asm` could be handed them, and
that is the one thing short-circuiting forbids — so they compile to a branch
and two constants instead, and the tree walker reaches the same answer by
simply not recursing.

### Commands

Every command starts with a colon:

| Command | Effect |
|---|---|
| `:mode`, `:mode <name>` | report or change the evaluation order |
| `:engine`, `:engine tree`, `:engine bytecode` | which engine runs a line |
| `:dis` | toggle the bytecode listing |
| `:vars` | every variable, its type and its value |
| `:help` | the list above |
| `:quit`, `:exit`, `:q`, EOF | leave |

Commands belong to the session and not to the language, so they are read only
where there is a session to read them: `-e` and a piped program have none, and
`:dis` in either is just an expression that starts with a colon and does not
parse. `tsafoshi -i` gives a session over a pipe, which is how the commands get
tested by a script.

Through stage 1.5 these were bare words, matched before the parser saw the
line, which made `mode`, `engine` and `dis` reserved. That was harmless while
the language had no identifiers and stopped being harmless the moment it did:
`mode` is a perfectly reasonable name for a variable. Rather than keep a list
of words you may not use, the colon moves the commands out of the language's
namespace entirely — no valid expression begins with one, so the two can never
collide again.

## Variables, and why they now need declaring

A variable is declared with `int`, which is the only type there is until stage
3 and carries no meaning yet beyond "one cell":

```
tsafoshi> int a = 10, b, c;
tsafoshi> b = c = 3
= 3
tsafoshi> a * b + c
= 33
tsafoshi> undeclared
          ^
error: undeclared identifier
```

Through stage 2.1 a name sprang into existence on first use and an unassigned
one read as `0`. That was a deliberate placeholder: with no declarations there
was nothing to call *undeclared*. Scope is what makes the question answerable,
so this is where it gets answered, and C99's answer is the one taken — no
implicit declarations, and a typo is an error rather than a new variable that
happens to be zero.

Assignment is still an **expression**, not a statement. It folds rightward, so
`b = c = 3` assigns to both, and it leaves its value behind, so the prompt has
something to echo. Its left side has to be a name, and that is checked after
the left side is parsed rather than by looking ahead:

```
tsafoshi> 5 = 3
          ^
error: left of '=' is not a variable
```


## Types

C's integer types, all of them, and the conversion rules that go with them:

| | | |
|---|---|---|
| `_Bool` | 1 | not a truncation but a test — `b = 256` gives 1, not 0 |
| `char` `signed char` `unsigned char` | 1 | three types, not two; plain `char` is signed here |
| `short` `unsigned short` | 2 | |
| `int` `unsigned int` | 4 | what everything narrower promotes to |
| `long` `unsigned long` | 8 | `long long` is accepted and is the same type |

The specifiers may arrive in any order, because C says they may:
`unsigned long int`, `long unsigned`, and `int long unsigned` are one type
written three ways. They are collected into a set and judged once, at the end,
which is the whole of `specifier.asm`.

```
tsafoshi> char c = 300; c
= 44
tsafoshi> unsigned u = -1; u
= 4294967295
tsafoshi> _Bool b = 256; b
= 1
tsafoshi> sizeof(long)
= 8
tsafoshi> (short)70000
= 4464
tsafoshi> 2147483647 + 1
= -2147483648
tsafoshi> :vars
  char c = 44
  unsigned int u = 4294967295
  _Bool b = 1
```

Literals carry a type too. `42` is an `int`; `2147483648` is a `long` because
it has to be; `10u`, `10L` and `10UL` are what they say. Hexadecimal and octal
arrived with them, so `0x1f` is 31 and `017` is 15. So did character
constants — `'A'` is 65, of type `int`, exactly as C99 says.

### Where the rules run

**All of it happens in the parser and none of it happens later.** By the time
either engine sees a tree, every conversion C99 asks for is already an explicit
node in it, and every operator has already been told whether it is the signed
one or the unsigned one.

That is the same trick `scope.asm` plays with names, for the same reason: the
parser is the last pass that knows, so it is the pass that decides, and what it
hands on is an answer rather than a question. Neither engine knows what a type
is. `vm.asm` has no idea `char` exists.

```
tsafoshi> :dis
tsafoshi> char c = 3; c + 1
    0000  push   3
    0009  conv   char
    0014  store  c
    0019  pop
    0020  load   c
    0025  conv   int
    0030  push   1
    0039  add
    0040  conv   int
    0045  halt
= 4
```

Read it as the rules being made visible. `conv char` is the narrowing that
makes 300 into 44. `conv int` on the loaded `c` is the integer promotion —
`char + int` is not char arithmetic, it is int arithmetic. And `conv int` after
the `add` is the result wrapping at *its* width rather than at the cell's,
which is what keeps `INT_MAX + 1` landing on `INT_MIN`.

### Which one wins

The usual arithmetic conversions, in full, and they collapse to two lines once
the promotions have run — because everything narrower than `int` has already
become one:

- at equal rank the **unsigned** type wins, so `int` against `unsigned int`
  is `unsigned int`;
- otherwise the **wider** one does, so `unsigned int` against `long` is `long`
  — a `long` is genuinely wide enough to hold every `unsigned int`, which is
  the condition the standard actually states.

The consequence is the one that catches people in real C, and it catches people
here too:

```
tsafoshi> int i = -1; unsigned u = 1; i < u
= 0
```

`-1` is not less than `1`, because `i` became `4294967295` before the
comparison happened. That is not a bug being reproduced for fun; it is the
language, and an interpreter that quietly got it "right" would be lying about
what the same code does when compiled.

### The shift is the exception

Every other binary operator converts both operands to a common type. A shift
does not: C99 promotes each side on its own and the result is the **left**
operand's type. Shifting is not symmetric, and pretending it were would make
`1L << n` depend on what `n` happened to be declared as.

```
tsafoshi> -8 >> 1
= -4
tsafoshi> (unsigned)-8 >> 1
= 2147483644
```

Same bits, same shift count, two different instructions — `sar` and `shr` —
chosen by the type of the thing being shifted.

### Casts, `sizeof`, and `void`

A cast is the explicit form of the conversion everything else does implicitly,
so it is the same node: `(char)300` is 44 for exactly the reason `char c = 300`
is.

`sizeof` folds to a constant while parsing, in all three of its spellings —
`sizeof(int)`, `sizeof(x)` and `sizeof x`. Its operand is never evaluated,
because only its type was ever wanted. The answer has type `unsigned long`,
which is what `size_t` is here.

`void` is a type now rather than a keyword that only appears in two places, so
a function can return one — and using that nothing as a value is an error with
a caret under it:

```
$ tsafoshi -e 'void v(void) { return; } int x = v();'
1 | void v(void) { return; } int x = v();
                                     ^
error: void has no value to use here
```

### Three files, because it is three jobs

| | |
|---|---|
| `type.asm` | what a type **is** — one table: width, signedness, rank, name |
| `convert.asm` | the **rules** — promotion, the common type, and narrowing a value |
| `specifier.asm` | the **spelling** — which combinations of keywords name which type |

The table is data that grows when a type is added; the rules are logic that
does not; the spelling is neither. Adding `float` would touch all three, in
three different ways, which is the argument for the split rather than against
it.

## Control flow

`if` / `else`, `while`, `do`-`while`, `for`, `break` and `continue`, all with
C99's semantics:

```
tsafoshi> int n = 27; int steps = 0;
tsafoshi> while (n != 1) {
     ...>     if (n % 2 == 0) n = n / 2; else n = 3 * n + 1;
     ...>     steps = steps + 1;
     ...> }
tsafoshi> steps
= 111
```

A declaration may not be the whole body of an `if` or a loop, because there
would be no block for it to be scoped to and it would silently leak into the
enclosing one:

```
tsafoshi> if (1) int x = 1;
                 ^
error: a declaration needs a block of its own
```

`break` and `continue` are checked while parsing, which is the only pass that
knows which statements are inside a loop — so the caret lands on the word
itself rather than somewhere in the generated code:

```
tsafoshi> continue;
          ^
error: not inside a loop
```

In a `for` loop, `continue` still runs the step. That is the whole reason
`for` is not simply a `while` with the step written at the bottom, and both
engines have to get it right separately: the VM by choosing where the label
goes, the tree walker by choosing when to clear the flag.

## Blocks and scope

A block is a list of statements and a scope, and the scope is the entire point
of the braces:

```
tsafoshi> int x = 1;
tsafoshi> { int x = 2; x = x * 10; }
tsafoshi> x
= 1
tsafoshi> :vars
  x = 1
```

Until this stage a variable *was* its name — the cell array was indexed by the
interned identifier, so there was exactly one `x` in the session and no way to
have a second. Now a name is resolved, once, while parsing, to a **storage
slot**; a block records a mark, and closing it discards both the bindings and
the storage they were using. Lookup runs backwards through the bindings, so the
innermost declaration wins, and that is all shadowing is.

The storage really is reclaimed, so a hundred sequential blocks each declaring
a variable cost one slot between them rather than a hundred.

By the time anything runs, no scope exists. The tree carries slot numbers, both
engines index them, and neither has any idea an identifier was ever involved.
That seam is deliberate: at stage 2.3 a slot becomes an offset into a call
frame, and only `scope.asm` has to notice.

It is also visible in the listing. `:dis` prints the name where one is still
bound and the raw slot where there is not, because after a block closes the
name is genuinely gone:

```
tsafoshi> :dis
tsafoshi> { int local = 7; local; }
    0000  push   7
    0009  store  $1
    0014  pop
    0015  load   $1
    0020  pop
    0021  push   0
    0030  halt
```

## Several lines at a time

A block does not fit on a line, so a submission is no longer a line. The REPL
keeps reading while braces are open and offers a continuation prompt:

```
tsafoshi> for (int i = 0; i < 3; i = i + 1) {
     ...>     printf("%d ", i);
     ...> }
0 1 2
```

Only braces are counted, and quotes and comments are skipped while counting —
a `{` inside a string closes nothing. An unbalanced *parenthesis* is a typo and
is reported, not waited on.

The continuation prompt is exactly as wide as the main one, and that is
load-bearing rather than cosmetic: a caret is placed by measuring a column from
the start of the line the error is on and adding the prompt width, so it lands
correctly on the fourth line of a block for the same reason it does on the
first.

## Functions

`int name(params) { body }`, defined at the top level, with `int` parameters
and an `int` result — which is every function there is until types arrive:

```
tsafoshi> int gcd(int a, int b) { while (b != 0) { int t = b; b = a % b; a = t; } return a; }
tsafoshi> gcd(1071, 462)
= 21
```

`return` with no expression, and falling off the end of a function, both mean
`return 0` — which is what C99 already says about `main`, generalised because
there is only one return type so far to generalise over.

A function is registered **before its body is parsed**. That is not tidiness;
it is the whole of what makes recursion possible, because the call inside the
body has to resolve to something, and the something is a record whose entry
point is not yet known:

```
tsafoshi> int fact(int n) { if (n <= 1) return 1; return n * fact(n - 1); }
tsafoshi> fact(12)
= 479001600
```

Arity is checked where the call is written, not discovered when the frame turns
out to be the wrong shape:

```
tsafoshi> gcd(4)
          ^
error: wrong number of arguments
```

Redefinition is refused rather than allowed to win. At a prompt it is tempting
to let the second definition replace the first, but calls already compiled
against the first would still be pointing at it, and "the function I just fixed
did not change" is a worse experience than being told to pick another name.

Mutual recursion needs a way to declare a function without defining it, which
is a prototype. The type system it needed arrived at stage 3.2; the prototype
itself is still to come, and belongs with the declarator work in 3.3.

## The call stack

A local is not a variable with a different name — it is an **offset into the
frame of the call that is running**. That is what makes recursion work at all:
the same offset is a different cell on every call.

```
tsafoshi> :dis
tsafoshi> int sq(int n) { return n * n; }
function sq:
    0000  loadl  fp+0
    0005  loadl  fp+0
    0010  mul
    0011  ret
    0012  push   0
    0021  ret
    0022  push   0
    0031  halt
```

`loadl` and `storel` are frame-relative where `load` and `store` are absolute,
and the node knew which to use because `scope.asm` knew, back when a scope
still existed. The `push 0; ret` at `0012` is the fall-off-the-end case,
reached only by a body that did not return for itself.

The `push 0; halt` at `0022` is a second listing, not part of the function: it
is what the *line* compiled to. A definition does nothing when it runs — its
whole effect happened while it was being read — so the line is empty, and an
empty line still has to answer with something.

There is no argument-passing convention to speak of, and that is the useful
part. Parameters are declared into the function's scope **first**, so they land
at frame offsets 0, 1, 2… The caller pushes its arguments onto the operand
stack in order, where they end up contiguous; `call` moves that block into the
bottom of the new frame. One copy, and an agreement about declaration order.

```
tsafoshi> int add(int a, int b) { return a + b; }
tsafoshi> add(3, 4)
    0022  push   3
    0031  push   4
    0040  call   add
    0045  halt
= 7
```

`call` reads the frame size out of the function table at run time rather than
carrying it in the instruction. That is deliberate groundwork: at stage 6 a
frame containing a variable-length array will not have a size known when the
call was compiled, and this is already the shape that copes.

Both engines share the frame storage itself — the same cells, indexed the same
way — while disagreeing completely about how a call is made. The VM keeps a
frame pointer and its own stack of return records. The tree walker recurses on
the machine stack and treats a C return as one more kind of unwinding, beside
`break` and `continue`. Sharing the cells is what makes the disagreement
detectable: if they differ about a call, it shows up as a wrong answer rather
than as two private truths.

Recursion is bounded, and says so rather than taking the process down with it:

```
tsafoshi> int inf(int n) { return inf(n + 1); }
tsafoshi> inf(1)
          ^
error: too much recursion
```

## Running a file

```sh
$ tsafoshi examples/fizzbuzz.c
```

The whole file is one submission — which works only because a submission
stopped being a line at stage 2.2 — and then `main` is called, by a node built
by hand and handed to the same `exec_run` the prompt uses. So a file is run by
exactly the route anything else is run by, on either engine.

`main`'s return value is the process's exit status:

```sh
$ cat > answer.c <<'END'
int main(void) { return 42; }
END
$ tsafoshi answer.c; echo $?
42
```

Errors carry a line number and print the line, because there is no prompt to
have echoed it:

```
$ tsafoshi broken.c
5 |     return n / 0;
                 ^
error: division by zero
```

Both presentations are the same fact — a column measured from the start of the
line the error is on. At a prompt the terminal already printed that line, so
the caret only has to clear the prompt; reading a file, nothing did, so the
line is printed first.

A file is one of four things the command line can name; the rest are below.

### `#include`, and where `main` goes

**The standard library is already there**, so `#include <stdio.h>` has nothing
left to do — there is no separate translation unit to declare `printf` into and
no linker to resolve it afterwards. But real C source has that line at the top
and has to keep working, so it is **accepted and ignored**:

```c
#include <stdio.h>

int main(void)
{
    printf("hello from the north star\n");
    return 0;
}
```

runs byte-for-byte as written, with the first line doing nothing at all.

The line is blanked out with spaces rather than deleted, so every byte after it
keeps the offset it had in the file and a caret still lands under the right
column. This is not the preprocessor — that is stage 5 — it is one directive
handled by not tripping over it.

**And there will be no header files.** When `#include` becomes real at stage 5,
`#include <module.h>` resolves to `module.c`, and a module is read exactly
once. No include guards, no `#pragma once`, and no forward declarations, since
nothing is ever declared twice for one to be needed. Includes still belong at
the top of a file, Python-style, because a name has to be known before it is
used and this interpreter reads a program in one pass.

That is a **real incompatibility with C**, not a shortcut around one, and it is
the biggest reason not to use Tsafoshi for anything that matters: source that
relies on a header being a separate, re-includable, declaration-only file will
not work here. It is deliberate. There is no separate translation unit and no
linker, so a header has nothing left to do — and a library that ships its `.c`
files is one this interpreter can read without a build system in front of it,
which is the point.

`main(int argc, char **argv)` needs pointers, so for now only `int main(void)`
is accepted and the other form is refused rather than silently mistaken for it.
The arguments themselves are not missing — they arrive through `argc()` and
`argv(n)`, below.

See [`examples/`](examples/) for programs that run today.

## The command line

```
usage: tsafoshi [options] [file] [arguments...]
       tsafoshi [options] -e code [arguments...]
       tsafoshi [options] -    [arguments...]
```

| Option | Effect |
|---|---|
| `-e`, `--eval` *code* | run *code* as one submission, then leave |
| `-i`, `--interactive` | stay at the prompt afterwards |
| `-q`, `--quiet` | no banner |
| `--engine` *name* | `bytecode` or `tree`, before anything runs |
| `--mode` *name* | `bodmas`, `ltr` or `rtl`, likewise |
| `-v`, `--version` | print the version and leave |
| `-h`, `--help` | print the usage and leave |
| `--` | end of options; everything after belongs to the program |

The shape is Python's, because Python's is the one people already have in
their fingers. Two rules do all the work: **the first non-option argument is
the source, and everything after it is the program's** — not read as an option
however much it looks like one — and `--` says so explicitly, for the file
genuinely called `-e`.

```sh
$ tsafoshi -e '2 + 3 * 4'
= 14
$ tsafoshi --mode ltr -e '2 + 3 * 4'
= 20
$ tsafoshi -e 'int n = 5; printf("n squared is %d
", n * n);'
n squared is 25
```

`-e` is one submission typed somewhere other than the prompt, so it behaves
like one: a bare expression at the end is answered, a trailing `;` silences it,
and `main` is called only if the code bothered to define one. Anything else
would make the flag a different language from the prompt it imitates.

### A terminal gets a session, a pipe gets a program

With no file and no `-e`, what happens depends on **who is on the other end of
standard input**:

```sh
$ tsafoshi                          # a terminal: the REPL, banner and all
$ echo 'printf("%d
", 6 * 7);' | tsafoshi
42
```

That is one `sys_isatty` call and it settles three things at once — whether to
print a banner, whether to print prompts, and how an error draws its caret.
They are the same question asked three ways: is anyone watching the screen. A
prompt down a pipe is not a prompt; it is the first thing the reader on the
other end has to learn to ignore.

`-i` overrides the guess in both directions. On its own it means *a session,
whatever standard input is* — which is how the REPL gets tested by a script:

```sh
$ printf ':engine tree
int sq(int n) { return n * n; }
sq(9)
' | tsafoshi -i
engine: tree
= 81
```

After a file or a `-e` it means *stay*, and everything the program defined is
still there to talk to, because the names, globals, functions and their code
all outlive the submission that made them.

### Exit status

| | |
|---|---|
| `0` | it worked; or `main` returned 0; or a session ended |
| whatever `main` returned | a program that ran to the end |
| `1` | something went wrong: a parse error, a runtime error, an unreadable file |
| `2` | the *command line* was wrong — an unknown option, or one missing its value |

Two failure codes rather than one, because a shell script wants to tell "your
program is broken" apart from "you called me wrong".

### `argc()`, `argv(n)`, and `exit(n)`

Three builtins joined `printf` at this stage:

| | |
|---|---|
| `argc()` | how many arguments the program was given, `argv(0)` included |
| `argv(n)` | one of them, as a NUL-terminated string |
| `exit(n)` | stop now, with that status |

```c
#include <stdio.h>

int main(void)
{
    int i;

    printf("%d argument", argc());
    if (argc() != 1)
        printf("s");
    printf(":
");

    for (i = 0; i < argc(); i = i + 1)
        printf("  %d  %s
", i, argv(i));

    return 0;
}
```

```sh
$ tsafoshi examples/args.c alpha beta
3 arguments:
  0  examples/args.c
  1  alpha
  2  beta
```

Functions rather than `main`'s parameters, and that is a limitation stated
honestly rather than a design: naming `char **argv` needs a pointer type, and
pointers are stage 3.3. The information is the same either way — a string
literal has been an address in a cell since stage 2.1, and `argv`'s strings are
addresses of exactly that kind — so `argv(argc())` is a null pointer for
precisely the reason it is in C. `printf` prints one as `(null)` rather than
following it, because the one honest way to walk off the end of the arguments
should not also be the way to bring the interpreter down.

`exit` leaves from wherever it is called — inside a loop, inside a function,
ten frames down — and there is nothing to unwind on the way: the frames are
ours, the arenas are ours, and the process is about to stop being.

All four builtins are one table in `builtin.asm`, one opcode, and one arm of
each engine. Adding a fifth is a line in that table, a line in `names.asm`, and
a constant.

## Comments

`/* ... */` and, because this is C99 and not C89, `//` to end of line. Both are
skipped by the same loop that skips whitespace, since nothing above the lexer
can tell the difference:

```
tsafoshi> int r = 6 /* six */ * 7;  // forty-two
tsafoshi> r
= 42
```

## Bytecode

The parser builds a tree, `compile.asm` flattens it to bytecode, and `vm.asm`
runs that in a dispatch loop. `:dis` shows the middle step:

```
tsafoshi> :dis
disassembly: on
tsafoshi> int i; int s = 0;
tsafoshi> while (i < 3) { s = s + i; i = i + 1; }
    0000  load   i
    0005  push   3
    0014  lt
    0015  jz     ->0063
    0020  load   s
    0025  load   i
    0030  add
    0031  store  s
    0036  pop
    0037  load   i
    0042  push   1
    0051  add
    0052  store  i
    0057  pop
    0058  jmp    ->0000
    0063  push   0
    0072  halt
```

A stack machine over 64-bit cells, one byte of opcode, and an operand only
where one is needed:

| Opcode | Operand | Effect |
|---|---|---|
| `halt` | | stop; the answer is on top of the stack |
| `push` | 8-byte immediate | push it |
| `mul` `div` `mod` `add` `sub` | `div` and `mod` take a 4-byte column | pop two, push the result |
| `shl` `shr` `lt` `gt` `le` `ge` `eq` `ne` `and` `xor` `or` | | likewise |
| `udiv` `umod` `ushr` `ult` `ugt` `ule` `uge` | `udiv` and `umod` take a column | the seven that mean something else when the operands are unsigned |
| `neg` `not` `bnot` | | rewrite the top in place |
| `pop` | | discard the top |
| `load` `store` | 4-byte storage slot | read a variable, or write one |
| `str` | 4-byte arena offset | push a literal's address |
| `bi` | 4-byte builtin, 4-byte count, 4-byte column | call a builtin on that many arguments, push its result |
| `jmp` | 4-byte target | go there |
| `jz` `jnz` | 4-byte target | pop one cell, go there if it was / was not zero |
| `loadl` `storel` | 4-byte frame offset | read or write a local, relative to the frame pointer |
| `call` | 4-byte function | enter a frame, move the arguments into it, jump |
| `ret` | | leave the frame; the value on top of the stack is the answer |
| `conv` | 4-byte type | narrow the top of the stack to that type and extend it back out |

The sixteen signed binary opcodes are numbered in token order, so the compiler
turns an operator token into its opcode with a subtract and an add rather than
a table lookup — and the VM, which still has the opcode in a register when the
handler is entered, indexes one table of `op.asm` routines with it. Sixteen
operators, one arm of the dispatch loop.

The seven unsigned ones sit immediately after them, so that one contiguous
range still covers every binary opcode and the dispatch arm did not have to
change. Which of the two an expression gets is a table lookup in the compiler,
keyed on the left operand's type — and nine of the sixteen entries in that
table are empty, because addition, multiplication, subtraction, the bitwise
three, a left shift and the two equalities produce the same bits whatever the
operands are called. That the table is mostly holes is the point of it.

`store` leaves its value on the stack, because assignment is an expression;
`pop` is what discards the values nobody wanted. Two invariants hold the whole
compiler up — **an expression leaves exactly one cell behind, and a statement
leaves none** — and everything else follows from them: why an expression
statement ends in a `pop`, why a declaration does, why a list of statements
needs no cleanup at the end, and why the operand stack is never checked for
underflow at run time.

The listing distinguishes four kinds of number, because they live in four
different spaces: `@n` is a column in the source, `+n` an offset into the
string arena, `->n` an offset into the listing itself, and `fp+n` an offset
into the frame of whichever call is running.

The buffer holds every function the session has defined, in definition order,
with the current line's code sitting on top of them and being overwritten by
the next line. Nothing is ever moved, which is what lets an entry point be a
plain offset that stays valid for the session — and it is why `:dis` lists a
range rather than the whole thing.

`div`, `mod` and `bi` are the only operations that can fail, and by the time
the VM is running there is no tree left to ask where they came from — so those
three carry the column they were written at, and a division by zero still gets
its caret in the right place. Nothing else pays for that.

`bi` is one opcode for every builtin rather than a calling convention because
the arguments are *already* contiguous and in order on the operand stack, which
is exactly the array a builtin wants. The tree walker has to build that array
by hand; the VM just passes a pointer into its own stack. Through stage 2.3
this opcode was called `printf`, because `printf` was the only thing it could
be; giving every builtin the same signature turned it into a table lookup and
one dispatch arm, which is also the door stage 4.1's library bridge walks in
through.

### Jumps, and holes that remember each other

A tree has no addresses in it, so control flow is where one has to be invented.
A forward jump is emitted before anyone knows where it goes, with a hole where
the target belongs, and the hole is filled in once the target is known.

`break` is harder, because a loop may contain any number of them and none can
be patched until the loop ends. Rather than keep a list, each unpatched hole
holds **the offset of the previous one** — so the jumps are threaded through
each other, an arbitrary number of breaks costs one word per loop, and nothing
is allocated. Offset zero is free to mean "end of chain" because the first byte
of the stream is always an opcode and never an operand.

The three loops are one emitter with the tests moved:

```
while   top: cond, jz end,  body, cont:        jmp top,  end:
for     top: cond, jz end,  body, cont: step,  jmp top,  end:
do      top:                body, cont: cond,  jnz top,  end:
```

Where `cont` lands is the whole of what makes `continue` correct in each: the
step still runs in a `for`, and the condition still gets tested in a `do`.

### Two engines, on purpose

The tree walker from stage 1 is still there, and `engine tree` switches back to
it. It is not a fallback. It is an oracle: two independent implementations of
the same semantics, which must agree on every input, so a bug in either one
shows up as a disagreement rather than as a wrong answer nobody notices.

Both call the same routines in `op.asm`, so they cannot disagree about what
`%` means — only about order, operand plumbing, and the encoding. Those are
exactly the things a new execution layer gets wrong.

Control flow is where they stop resembling each other, and that is when the
arrangement starts earning its keep. The VM jumps: `break` is an address. A
recursive walker cannot jump out of its own call chain, so it sets a flag and
every statement rule tests it on the way back out. Two genuinely different
mechanisms, one required answer.

## Order of operations

The default is **BODMAS**: brackets first, then `* / %`, then `+ -`, and so on
down the C99 ladder, with equal-strength operators folded left. That is exactly
what C99 specifies, so the default needs no apology — and the rows below did
not have to be renumbered when eleven more operators arrived at this stage,
because the ladder had their levels reserved from the start.

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

That reservation has now been spent. Shifts, comparisons, equality and the
bitwise operators took the levels held for them, and a mode is still a single
row of bytes plus the bump — eighteen bytes now rather than five, and not one
line of `parser.asm` changed to widen it.

The two short-circuiting operators sit at the end of that row. They carry a
precedence like everything else, so the climbing loop handles them; they are
simply not operators `op.asm` can be asked for, which the token numbering says
out loud by stopping the evaluable range one short of them.

## Layout

```
src/
  main.asm              _start -> repl_main. The entry point, and nothing else.
  core/                 platform-independent, assembled once
    tsafoshi.inc        shared constants and token kinds
    cli.asm             the command line: options, source, the program's argv
    repl.asm            the read-eval-print loop, and whether to have one
    script.asm          running a file, a pipe or a -e, and reaching main
    readline.asm        buffered line input, and the multi-line submission
    lexer.asm           source text -> tokens, comments and all
    names.asm           identifier interning: text -> a stable slot
    scope.asm           lexical scope: a name -> the storage slot it means
    strings.asm         string literals: escapes, and an arena that interns
    parser.asm          tokens -> a syntax tree (structure only)
    ast.asm             node storage: one arena, reset per line
    eval.asm            tree -> value directly (the oracle engine)
    func.asm            the function table: arity, frame size, entry, body
    compile.asm         tree -> bytecode
    code.asm            the code buffer, reset per line
    vm.asm              the dispatch loop and its operand stack
    disasm.asm          bytecode -> a listing
    exec.asm            which engine runs, and the commands that switch it
    op.asm              operator semantics (values), signed and unsigned
    type.asm            what a type is: width, signedness, rank, name
    convert.asm         promotion, the common type, and narrowing a value
    specifier.asm       which combinations of keywords name which type
    vars.asm            global storage, the managed C stack, and ":vars"
    printf.asm          the format-string interpreter
    builtin.asm         the builtin table: printf, argc, argv, exit
    mode.asm            evaluation order, and the ":mode" command
    error.asm           diagnostics and the caret
    format.asm          number formatting, output helpers
  linux/input.asm       console I/O and isatty, Linux syscalls
  linux/readfile.asm    files and argv, Linux syscalls
  windows/input.asm     console I/O and isatty, Windows kernel32
  windows/readfile.asm  files and argv, Windows kernel32
tests/corpus.txt        the lines the two engines are diffed over
tools/prettier.py       source layout normalizer
Makefile                the build, and the only file that names a platform
run.bat                 the same build for native cmd, which has no make
run.sh                  a shim over make, for muscle memory
```

Start reading at `src/main.asm`. It is five instructions: hand the loader's
stack to `sys_args_init`, align the stack, cut the frame chain, call
`repl_main`. Both platforms share it — Linux `ld` picks
`_start` up by default and the Windows linkers are passed `/entry:_start`, so
there is no conditional assembly anywhere in the tree.

Each `.asm` is its own translation unit; they are assembled separately and
linked. Cross-module symbols are explicit `global` / `extern`, so the
dependency graph is visible at the top of every file.

The build is `src/main.asm` plus `src/core/*.asm` plus exactly one
`src/<platform>/`. The core never names a platform.

### The module seams

| Seam | Interface |
|---|---|
| lexer → parser | `lex_init`, `lex_next`, and one token of lookahead in `tok_kind` / `tok_val` / `tok_pos` |
| lexer → names, strings | `name_intern` and `str_intern` — a lexeme becomes a value in the lexer, so the parser never sees characters |
| parser → ast | `ast_num` / `ast_binary` / `ast_var` / `ast_call` and the rest, each returning a node or zero |
| parser → mode | `mode_prec(kind)` and `mode_bump` — the parser never hardcodes an order |
| parser → scope | `scope_declare(name)` and `scope_lookup(name)` — an identifier goes in, a storage slot comes out, once |
| tree → engine | `exec_run(statements, value)`, which is either `eval_program` or `code_compile` then `vm_run` |
| engine → op | `op_apply(lhs, rhs, kind, pos)` and the `op_*` routines — the engine decides order, `op.asm` produces every value |
| engine → vars | `var_get(slot)` / `var_set(slot, value)` for globals, `var_local_get` / `var_local_set` for a frame — slots only, never text |
| engine → vars | `frame_enter(size)` / `frame_args(from, n)` / `frame_leave(fp)` — the managed C stack, shared by both engines |
| parser → func | `func_declare(name, arity)` before the body, `func_set_body` / `func_set_frame` after it |
| engine → func | `func_arity` / `func_frame` / `func_entry` for the VM, `func_body` for the walker |
| engine → builtin | `builtin_run(id, args, count, pos)` — one array of cells, whichever engine built it, and one signature for every builtin |
| parser → specifier | `type_build(specifiers, longs)` — a set of keywords in, a type out, judged once |
| parser → convert | `type_promote`, `type_common` — the rules that decide what an operator's operands become |
| parser → type | `type_size`, `type_unsigned`, `type_rank`, `type_name` — the four questions, one table |
| engine → convert | `type_convert(value, type)` — the only definition of what becoming a `char` does, called by both |
| repl → cli | `cli_parse`, then `cli_kind` / `cli_text` / `cli_argc` — what was asked for, decided once, before anything is read |
| compiler → code | `code_op` / `code_i64` / `code_u32` to write, and `code_jump` / `code_patch` for a jump whose target is not known yet |
| compiler → vm | the code buffer in `code.asm`; neither module owns the memory, so `disasm.asm` reads it without either knowing |
| anything → error | `err_expected` / `err_divzero` / `err_notlvalue` / `err_badconv` and the rest, each taking a position |
| core → platform | the nine `sys_*` routines below |

The tree is the seam that matters. The parser builds nodes and never computes
a value; a consumer walks nodes and never looks at a token. That is what made
the bytecode compiler a purely additive change — it is a second consumer of
the same tree, and not one line of the lexer or the parser moved to get it.

`op_apply`, `ast_eval`, `emit_node` and the VM's inner loop all dispatch
through jump tables, indexed by token kind, node kind, node kind and opcode
respectively.

Four of those tables are the same list read four ways. The operator tokens are
numbered in C99 precedence order; `mode.asm`'s row, `op.asm`'s table, the
opcode numbering and the VM's routine table all follow that order, so adding an
operator means adding one line to each rather than reasoning about any of
them.

Every AST node is the same six cells whatever its kind — the three pointer
slots get reused rather than added to, so a `while` loop, an argument list and
a binary operator all cost the same. The sixth is the type, added at stage 3.2
and read only for expressions; the alternative was packing it into the kind,
and a node is cheap enough that hiding a field inside another one would have
been the worse trade. `tsafoshi.inc` records which slot means
what. Because the shape never varies, every constructor in `ast.asm` is the
same routine with its arguments in a different order, which is exactly how it
is written.

`for` is the one rule that wanted a fourth slot, and did not get one. Its init
clause is lifted out into an ordinary statement in front of the loop, inside
the scope the rule opens for it — which is also precisely what C99 says the
scope of `for (int i = ...)` is, so the shortcut and the standard agree.

Nodes come out of a bump-allocated arena that the REPL resets once per line,
so a tree costs one pointer bump per node and nothing at all to free. Running out raises `expression too complex`; `AST_CAP` is 16384 nodes, which a
line typed at a prompt cannot reach but a `.c` file read in one submission
could, so it is a real guard rather than a formality.

### The platform contract

A target provides nine routines across two files, and the entry point is not
one of them — `src/main.asm` is shared. `input.asm` is the console:

| | |
|---|---|
| `sys_write_stdout` | `rsi` = buffer, `rdx` = length |
| `sys_write_stderr` | `rsi` = buffer, `rdx` = length |
| `sys_read_stdin` | `rsi` = buffer, `rdx` = capacity → `rax` = bytes, `<= 0` at EOF |
| `sys_isatty` | `rdi` = 0 for stdin, 1 for stdout → `rax` = 1 if it is a terminal |
| `sys_exit` | `edi` = status, does not return |

and `readfile.asm` is files and the command line:

| | |
|---|---|
| `sys_args_init` | `rdi` = the stack as the loader left it, called once, first |
| `sys_argv` | `rdi` = index → `rax` = that argument, or 0 |
| `sys_open_read` | `rdi` = path → `rax` = a file, negative if it could not be opened |
| `sys_read_file` | `rdi` = file, `rsi` = buffer, `rdx` = capacity → `rax` = bytes, 0 at the end |
| `sys_close` | `rdi` = file |

Two files rather than one because they are two jobs, and because the split is
where the platforms genuinely diverge rather than merely differ in spelling: a
Linux file is an integer read by the same call that reads a pipe, and a Windows
file is an opaque handle from `CreateFileA`. Likewise the command line, which
Linux leaves on the initial stack and Windows makes you ask for and split
yourself. `sys_isatty` is the same story a third time: there is no such
syscall on Linux, so it asks the descriptor for terminal settings and reads the
kernel's objection, while Windows calls `GetConsoleMode` and reads its
failure. `src/main.asm` hands `rsp` to `sys_args_init` without knowing which
of those is true, and each target decides whether that was useful.

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
straightforward forks: reimplement the eight `sys_*` routines, keep the
register contract, and `src/core/` is untouched.

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

**Why `printf` is a builtin, and what that becomes.** Stage 4 is the standard
library, written here rather than linked from anywhere, and 4.1 is the table
and the binding that gets to it. `printf` was built the same way early because
it exercises the parts that matter — a call node, an argument list, arguments
arriving contiguously on the operand stack, and a runtime error raised from
inside the VM with a caret that still lands in the right column — without
needing an address-space model or a `char *` that is a genuine host pointer.
Stage 3.1 already generalised it: four builtins now share one signature and one
opcode. What stage 4 adds is two hundred more entries in that table and the
lazy binding that keeps them free until something asks.

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
