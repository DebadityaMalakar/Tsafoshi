# The Tsafoshi language

A reference for the language as it exists **today**, at stage 3.2 — not the
language it is planned to become. Where it differs from C99, this says so and
says why.

[`README.md`](README.md) is the project: how it is built, how it works inside,
and where it is going. This is the part you need if you are writing a program
for it.

---

## The short version

Tsafoshi is C99, minus what has not been built yet, plus a small number of
deliberate departures. **Those departures are the reason this file exists**, so
they come first:

| | Tsafoshi | C99 |
|---|---|---|
| **Header files** | There are none. `#include <x.h>` will resolve to `x.c` and read it once. Today the line is accepted and ignored. | A header is a separate, re-includable, declaration-only file |
| **Evaluation order** | Switchable at run time — `:mode bodmas`, `ltr`, `rtl` | Fixed by the grammar |
| **A trailing expression** | Is the submission's value, and gets printed | Not a thing outside a statement |
| **Top-level statements in a file** | Run, before `main` | Not permitted outside a function |
| **`main`** | `int main(void)` only. Arguments arrive through `argc()` and `argv(n)` | `int main(int argc, char **argv)` |
| **Identifiers** | Any Unicode, transliterated to an ASCII shortcode: `💀` is `:skull` | Implementation-defined; usually ASCII plus `\u` escapes |
| **Signed overflow** | Wraps, two's complement | Undefined |
| **Shift count out of range** | The low six bits are used | Undefined |
| **`INT64_MIN / -1`** | `INT64_MIN` | Undefined (and traps on x86) |
| **`printf("%s", NULL)`** | Prints `(null)` | Undefined |
| **`printf` length modifiers** | Read and ignored; the cell's full 64 bits are printed | Select the argument's width |
| **`printf` precision** | Applies to `%s` only | Applies to every conversion |
| **`'ab'`** | The first byte | Implementation-defined, usually packed |
| **Function redefinition** | Refused | Refused, but at a prompt people expect replacement |
| **Duplicate type specifiers** | Not diagnosed: `short short x` means `short` | A constraint violation |
| **`++x`, `--x`** | Parse as `+(+x)` and `-(-x)` — silently, and they do nothing | Increment and decrement |

The last one is the trap worth knowing about. `++` and `--` do not exist yet,
and because unary `+` and `-` nest, writing them is not an error — it is a
no-op or a double negation. That will stop being true when they are
implemented; until then, use `x = x + 1`.

**Not for production.** The header departure alone means source that treats a
header as a declaration-only file will not work here, and that is the design
rather than a gap in it.

---

## Running something

| | |
|---|---|
| `tsafoshi file.c` | run a program; the exit status is what `main` returned |
| `tsafoshi -e 'code'` | run one submission, as if typed at the prompt |
| `tsafoshi` | a session, if standard input is a terminal |
| `... \| tsafoshi` | a program, if it is not |
| `... \| tsafoshi -i` | a session anyway |

`README.md` has the full command line. What matters here is that a **file** and
a **submission** are the same thing to the parser, and the only difference is
what happens afterwards: a file goes on to call `main`, and a submission
answers with its last expression.

---

## Lexical structure

### Comments

`/* ... */` and `//` to end of line. Both are skipped by the same loop that
skips whitespace, so a comment may appear anywhere whitespace may.

### Identifiers

A letter, an underscore, or **any non-ASCII character**, followed by any
number of those or digits.

Non-ASCII characters are transliterated into ASCII before anything downstream
sees them, one codepoint at a time:

| Written | Becomes | Because |
|---|---|---|
| `💀` | `:skull` | a name in the table |
| `☝😭` | `:point_up:sob` | one shortcode per codepoint |
| `café` | `caf:u00e9` | not an emoji, so the codepoint in hex |
| `你好` | `:u4f60:u597d` | likewise |
| `x🔥y` | `x:firey` | ASCII passes through untouched |
| `👍🏽` | `:thumbsup:tone3` | a skin tone is its own codepoint |
| `❤️` | `:heart` | the variation selector is dropped |
| `🫩` | `:u1fae9` | not in the table, so hex |

This is the Discord convention, and it is a **storage** decision rather than a
syntax one: the name table stays fixed-width ASCII, so every comparison, every
listing and every error message carries on knowing nothing about Unicode. Only
two files do — `utf8.asm` and `shortcode.asm`.

Consequences worth knowing:

- `❤️` and `❤` are **the same identifier**. The variation selector says how to
  draw the character before it and is not part of anybody's name.
- `👍` and `👍🏽` are **different identifiers**, because the skin tone is a real
  codepoint and quietly conflating them would be worse than refusing both.
- The shortcode is what you see in `:vars`, in the disassembler and in error
  messages, because that is genuinely what is stored.
- A name is at most 63 bytes *after* transliteration, so about three emoji.

Names are case-sensitive. There is no limit on how many are distinct beyond
`NAME_CAP` below.

### Keywords

```
break     continue  do        else      for       if        return
sizeof    void      _Bool     char      short     int       long
signed    unsigned
```

Seventeen. Everything else C99 reserves — `switch`, `case`, `default`, `goto`,
`const`, `static`, `extern`, `volatile`, `typedef`, `enum`, `struct`, `union`,
`register`, `auto`, `inline`, `restrict`, `float`, `double` — is currently an
ordinary identifier, so using one gives an "undeclared identifier" error rather
than a syntax error. That is a symptom of them not existing yet, not a decision.

### Integer literals

| | |
|---|---|
| Decimal | `42` |
| Octal | `017` — a leading zero, as in C |
| Hexadecimal | `0x1f`, `0X1F` |
| Suffixes | `u` `U` `l` `L` `ll` `LL` and combinations |

No binary `0b` literals: they are a GNU extension rather than C99.

**A literal's type is the narrowest its suffix allows that can hold it.** `42`
is an `int`; `2147483648` is a `long` without anybody writing `L`; `10u` is
`unsigned int`; `10UL` is `unsigned long`. A literal too large for `long`
wraps silently, which is a gap rather than a decision.

### Character constants

`'A'`, `'\n'`, `'\x41'`, `'\101'`. Type `int` and value the byte, sign-extended
— so `'\xff'` is `-1`, because plain `char` is signed here.

`''` is an error. A multi-character constant such as `'ab'` is **the first
byte** — 97 — rather than the implementation-defined jumble C99 permits or the
error it might have been.

### String literals

Bytes in double quotes, with the escapes below. A literal is interned once and
its value is its **address**, of type `long` until pointers exist.

```
\a \b \f \n \r \t \v \\ \' \" \?      \0 .. \377 (octal)      \xNN (hex)
```

Adjacent string literals are **not** concatenated. `"ab" "cd"` is an error.

UTF-8 inside a string is passed through untouched — the lexer only cares about
the closing quote and the backslash — so printing emoji works and always has.

---

## Types

| | `sizeof` | |
|---|---|---|
| `void` | — | a return type; not a variable |
| `_Bool` | 1 | a **test**, not a truncation: `b = 256` gives 1 |
| `char` | 1 | signed |
| `signed char` | 1 | a distinct type from `char` |
| `unsigned char` | 1 | |
| `short`, `unsigned short` | 2 | |
| `int`, `unsigned int` | 4 | what everything narrower promotes to |
| `long`, `unsigned long` | 8 | |
| `long long`, `unsigned long long` | 8 | accepted, and the same type as `long` |

Specifiers may be written in any order: `unsigned long int`, `long unsigned`
and `int long unsigned` are one type spelled three ways. Duplicates are not
diagnosed, so `short short x` is accepted and means `short`; a repeated `long`
*does* count, because `long long` has to.

`signed unsigned` is rejected, as is `short char` and anything else no ordering
makes meaningful.

### The invariant

Every value on the evaluation stack occupies 64 bits, whatever its type. What
keeps that honest is one rule:

> A cell always holds its type's value **extended to 64 bits** — sign-extended
> when the type is signed, zero-extended when it is not.

So narrowing happens once, where a value is produced or stored, and nothing
afterwards has to ask how wide anything is. `char c = 300` stores 44; `c + 1`
is 45 because what was loaded was already 44.

### Conversions

The C99 rules, in full.

**Integer promotions.** Anything narrower than `int` becomes `int` before any
arithmetic. So `char + char` is `int` arithmetic, and a `short` overflows into
an `int` rather than wrapping.

**The usual arithmetic conversions**, after promotion, collapse to two lines:

- at equal rank the **unsigned** type wins — `int` against `unsigned int` is
  `unsigned int`;
- otherwise the **wider** one does — `unsigned int` against `long` is `long`,
  because a `long` holds every `unsigned int`.

The consequence that catches people in real C catches people here too:

```
tsafoshi> int i = -1; unsigned u = 1; i < u
= 0
```

`-1` is not less than `1`, because `i` became `4294967295` first. An
interpreter that quietly got that "right" would be lying about what the same
code does compiled.

**Shifts are the exception.** There is no common type: each operand is promoted
on its own and the result is the **left** operand's type. Which is why `>>` is
arithmetic on a signed left operand and logical on an unsigned one:

```
tsafoshi> -8 >> 1
= -4
tsafoshi> (unsigned)-8 >> 1
= 2147483644
```

**Where conversions happen:** an initialiser, an assignment, an argument, a
return value, a cast, and both operands of every binary operator. All of it is
worked out while parsing, so a conversion is a node in the tree rather than a
decision at run time.

### `sizeof`

`sizeof(type)`, `sizeof(expression)` and `sizeof expression`. Folded to a
constant while parsing; the operand of the latter two is never evaluated. The
result has type `unsigned long`, which is what `size_t` is here.

### Casts

`(type) expression`. The explicit form of the same conversion everything else
does implicitly — `(char)300` is 44 for the reason `char c = 300` is.

`(void)expr` is how you discard a value. A void-typed expression at a prompt
prints nothing, because it has no answer and inventing a `0` would be worse.

---

## Expressions

### Operators

Tightest binding first.

| | | |
|---|---|---|
| unary | `-` `+` `!` `~`, casts, `sizeof` | right to left |
| 10 | `*` `/` `%` | |
| 9 | `+` `-` | |
| 8 | `<<` `>>` | |
| 7 | `<` `>` `<=` `>=` | yield `1` or `0` |
| 6 | `==` `!=` | |
| 5 | `&` | |
| 4 | `^` | |
| 3 | `\|` | |
| 2 | `&&` | short-circuits |
| 1 | `\|\|` | short-circuits |
| — | `=` | right to left; the left side must be a variable |

Plus parentheses and function calls.

`&&` and `||` are the only operators with no opcode behind them: both operands
would have to be values first, which is the one thing short-circuiting forbids,
so they compile to a branch and two constants.

An assignment's value is the value **stored**, not the value written — so with
`char c`, the expression `c = 300` is 44.

### Evaluation order is switchable

This one has no equivalent in C. The precedence table is data, and there are
three of them:

| | |
|---|---|
| `bodmas` | C99's own, the default |
| `ltr` | every binary operator equal, folding left |
| `rtl` | every binary operator equal, folding right |

```
$ tsafoshi -e '2 + 3 * 4'
= 14
$ tsafoshi --mode ltr -e '2 + 3 * 4'
= 20
```

`:mode ltr` at a prompt, or `--mode ltr` on the command line. It exists to keep
the parser honest — no rule may assume a fixed order, because the order is not
known until run time — and it is a genuine language-level difference while it
is switched on.

### Not implemented

`?:`, the comma operator, `++`, `--`, compound assignment (`+=` and the rest),
`&`, unary `*`, subscripting, `.` and `->`, and compound literals.

`++x` and `--x` parse as nested unary `+` and `-` and do nothing. This is the
one silent difference in the language; everything else in this list is an error.

---

## Statements

```
;                                       the empty statement
{ statement* }                          a block, with its own scope
type declarator ( "," declarator )* ;   a declaration
expression ;
if ( expression ) statement ( else statement )?
while ( expression ) statement
do statement while ( expression ) ;
for ( init? ; condition? ; step? ) statement
break ;
continue ;
return expression? ;
```

A **block** is a scope. A declaration inside one is gone at the closing brace,
and its storage is reused — so shadowing works, and a hundred sequential blocks
each declaring a variable cost one slot between them.

Declarations may appear anywhere in a block, and in a `for` init clause, which
is C99 rather than C89. The `for` init clause's scope is the loop, exactly as
C99 says.

`break` and `continue` outside a loop are errors with a caret on the word.
`return` outside a function likewise.

An omitted `for` condition is always true. `return;` with no expression is
`return 0`, which is also what falling off the end of a function means.

**A declaration is not a statement where a body is expected.** `if (x) int y;`
is an error, because there would be no block for `y` to be scoped to.

---

## Functions

```c
int square(int n) { return n * n; }
void nothing(void) { return; }
unsigned wrap(unsigned x) { return x * 2; }
```

- Any type may be returned, `void` included.
- The parameter list is `void`, empty, or typed parameters. Untyped is an error.
- Definitions are top level only; nested functions are an error.
- A function may call itself — it is registered before its body is parsed.
- **Mutual recursion does not work yet**, because it needs prototypes and
  prototypes do not exist.
- **Redefinition is refused.** A call compiled against the first definition
  would still point at it, so being told to pick another name is better than
  "the function I just fixed did not change".
- Arguments are converted to the parameter types; the return value is converted
  to the return type.
- A `void` function's result used as a value is an error.

Locals live in a frame on a managed stack, so recursion works and each call has
its own copy.

| | |
|---|---|
| Parameters per function | 16 |
| Arguments per call | 16 |
| Nested calls | 256 |
| Cells of local storage, all frames | 4096 |

---

## Programs

A `.c` file is read as **one submission**. Its top-level statements run, and
then `main` is called if there is one; `main`'s return value is the process's
exit status.

```c
#include <stdio.h>

int main(void)
{
    printf("hello\n");
    return 0;
}
```

`int main(void)` is the only accepted form. `main(int argc, char **argv)` needs
a pointer type and is refused rather than silently mistaken for the other.

### `#include`

**The standard library is already here**, so `#include <stdio.h>` has nothing
to do: there is no separate translation unit to declare `printf` into and no
linker to resolve it afterwards. The line is **accepted and ignored** — blanked
out with spaces rather than deleted, so every byte after it keeps the offset it
had and a caret still lands under the right column.

When `#include` becomes real, `#include <module.h>` will resolve to `module.c`
and read that module **once**. No include guards, no `#pragma once`, and no
forward declarations, because nothing is ever declared twice for one to be
needed. Includes still belong at the top of a file, since a name has to be
known before it is used and a program is read in one pass.

This is a real incompatibility with C, not a shortcut around one.

Other `#` directives are ignored the same way. There is no preprocessor yet:
no `#define`, no `#if`, no macros.

---

## Builtins

Four, and they are ordinary calls with their arity checked while parsing.

| | | |
|---|---|---|
| `printf(format, ...)` | `int` | bytes written |
| `argc()` | `int` | arguments the program was given, `argv(0)` included |
| `argv(n)` | `long` | one of them, as a NUL-terminated string; `argv(argc())` is null |
| `exit(n)` | — | stop now, with that status, from wherever you are |

### `printf`

Conversions: `%d` `%i` `%u` `%x` `%X` `%o` `%c` `%s` `%p` `%%`.
Flags: `-` and `0`. Width, as a literal number.

**Precision applies only to `%s`**, where it caps the length. On a numeric
conversion it is parsed and ignored, so `%.3d` of 5 is `5` rather than `005`.
That is a gap rather than a decision.

Length modifiers (`h`, `l`, `ll`, `z`, `j`, `t`) are **parsed and ignored**,
because every argument is already a 64-bit cell. So `%d` on a `long` prints the
whole `long`, and `%u` prints the cell as an unsigned 64-bit number. Write the
modifier if you like — it costs nothing and documents intent — but it does not
select anything.

`%s` on a null pointer prints `(null)` rather than following it, so walking off
the end of `argv` cannot bring the interpreter down.

Variadic arguments get the default argument promotions, which is why passing a
`char` and reading `%d` works.

---

## Diagnostics

One error per submission — the first — with a caret under the column that
caused it.

At a prompt the terminal already echoed the line, so only the caret is printed:

```
tsafoshi> 4 / 0
            ^
error: division by zero
```

Reading a file nothing echoed it, so the line is printed first, with its number:

```
$ tsafoshi broken.c
6 |     return n / 0;
                 ^
error: division by zero
```

The column is counted in **screen columns**, not bytes, so a line containing an
emoji still puts the caret in the right place.

Errors are reported at parse time wherever possible — an unknown name, a wrong
argument count, a `break` outside a loop, a type that no combination of words
spells. What is left for run time is division by zero, a bad `printf`
conversion, recursion too deep, and the arena limits below.

---

## Limits

All of them are constants in `src/core/tsafoshi.inc` and all are guarded with a
real error rather than silently exceeded.

| | |
|---|---|
| Source per session | 65536 bytes |
| One physical input line | 1024 bytes |
| Distinct identifiers | 256 |
| Bytes per identifier | 63, after transliteration |
| Global variable slots | 512 |
| Bindings visible at once | 256 |
| Nested blocks | 32 |
| Nested loops the compiler tracks | 32 |
| Functions per session | 128 |
| Tree nodes per submission | 16384 |
| Bytecode per session | 65536 bytes |
| Evaluation stack | 1024 cells |
| String literal bytes | 8192 |
| Distinct string literals | 256 |

---

## Not implemented yet

Roughly in the order it is coming. `README.md` has the staged plan.

**Types and declarations.** Pointers, arrays, `struct`, `union`, `enum`,
`typedef`, prototypes, `const` / `volatile` / `static` / `extern`, `float` and
`double`.

**Expressions.** `?:`, the comma operator, `++` and `--`, compound assignment,
`&` and unary `*`, subscripting, `.` and `->`, compound literals, string
literal concatenation.

**Statements.** `switch` / `case` / `default`, `goto` and labels.

**The library.** Everything but `printf`: `<string.h>`, `<stdlib.h>`,
`<math.h>`, the rest of `<stdio.h>`, and the type and limit headers.

**The preprocessor.** `#define`, `#if`, macros, and `#include` actually
including something.

---

## Undefined behaviour that is defined here

C leaves these open. This interpreter does not, and a program that relies on
them is relying on Tsafoshi rather than on C.

| | |
|---|---|
| Signed overflow | Wraps, two's complement |
| Shift count outside the width | The low six bits are used |
| `INT64_MIN / -1` | `INT64_MIN`, rather than trapping |
| `INT64_MIN % -1` | `0` |
| `printf("%s", NULL)` | `(null)` |
| An uninitialised local | Zero — the frame is cleared on entry |
| A global with no initialiser | Zero |
| Reading a variable declared in a closed block's reused slot | Zero |

The last three are worth stating plainly: C calls them indeterminate and would
be within its rights to hand you whatever was there. Zeroing costs one loop per
call and makes a bug reproducible, which is the trade this project would rather
have.
