; SPDX-License-Identifier: MIT
;
; How the source spells a type.
;
; C lets the specifier keywords arrive in any order and says nothing about
; which -- "unsigned long int", "long unsigned", "int long unsigned" are all
; the same type -- so they cannot be judged as they are read. The parser
; collects them into a set instead and asks here once, at the end, and this
; file is the only place that knows which combinations of words mean something.
;
; That is the whole job, and it is why this is its own file: type.asm is the
; table of what types are, convert.asm is the arithmetic of moving between
; them, and this is the spelling. Adding "float" would touch all three, in
; three different ways, which is the argument for the split rather than
; against it.

%include "tsafoshi.inc"

    global  type_build

    section .text

; rdi = the specifier set, rsi = how many "long"s were written
; -> rax = the type, or -1 if that combination is not one.
;
; Everything rejected here is something like "short char" or "unsigned void" --
; combinations no ordering makes meaningful, as against orderings this happens
; not to accept.
type_build:
    test    rdi, SP_VOID
    jnz     .void
    test    rdi, SP_BOOL
    jnz     .bool

    mov     rdx, rdi
    and     rdx, SP_SIGNED | SP_UNSIGNED
    cmp     rdx, SP_SIGNED | SP_UNSIGNED
    je      .bad                        ; "signed unsigned" is not a type

    test    rdi, SP_CHAR
    jnz     .char
    test    rdi, SP_SHORT
    jnz     .short
    test    rsi, rsi
    jnz     .long

    mov     rdx, rdi
    and     rdx, SP_INT | SP_SIGNED | SP_UNSIGNED
    jz      .bad                        ; nothing was said at all
    test    rdi, SP_UNSIGNED
    jnz     .uint
    mov     eax, TY_INT
    ret
.uint:
    mov     eax, TY_UINT
    ret

.void:
    cmp     rdi, SP_VOID                ; and nothing else
    jne     .bad
    mov     eax, TY_VOID
    ret
.bool:
    cmp     rdi, SP_BOOL
    jne     .bad
    mov     eax, TY_BOOL
    ret

; "char", "signed char" and "unsigned char" are three types and not two, which
; is a distinction C makes here and nowhere else: plain int and signed int are
; the same type, plain char and signed char are not.
.char:
    test    rdi, SP_SHORT | SP_INT | SP_LONG
    jnz     .bad
    test    rsi, rsi
    jnz     .bad
    test    rdi, SP_UNSIGNED
    jnz     .uchar
    test    rdi, SP_SIGNED
    jnz     .schar
    mov     eax, TY_CHAR
    ret
.schar:
    mov     eax, TY_SCHAR
    ret
.uchar:
    mov     eax, TY_UCHAR
    ret

.short:
    test    rdi, SP_LONG
    jnz     .bad
    test    rsi, rsi
    jnz     .bad
    test    rdi, SP_UNSIGNED
    jnz     .ushort
    mov     eax, TY_SHORT
    ret
.ushort:
    mov     eax, TY_USHORT
    ret

; "long long" is accepted and is the same eight bytes "long" already was. That
; is a real C99 type this interpreter cannot tell apart from long, and saying
; so plainly is better than refusing to read a header that uses it.
.long:
    cmp     rsi, 2
    ja      .bad
    test    rdi, SP_UNSIGNED
    jnz     .ulong
    mov     eax, TY_LONG
    ret
.ulong:
    mov     eax, TY_ULONG
    ret

.bad:
    mov     rax, -1
    ret
