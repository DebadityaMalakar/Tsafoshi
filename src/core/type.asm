; SPDX-License-Identifier: MIT
;
; What a type is. One table, four questions, and nothing else.
;
; A type in this interpreter is a small number, and everything anybody wants to
; know about it -- how wide it is, whether it is signed, where it sits in C99's
; conversion ranking, what it prints as -- is a row here. Three files share
; that table and each does one thing with it: this one answers the questions,
; convert.asm applies the rules that are phrased in terms of the answers, and
; specifier.asm turns the words a programmer wrote into a row number.
;
; The 64-bit cell rule survives this stage, and this table is what makes it
; survive. A cell is always 64 bits wide; the invariant is that a value in one
; is always its type's value *extended to* 64 bits -- sign-extended when the
; type is signed, zero-extended when it is not. Narrowing therefore happens
; once, where a value is produced or stored, and nothing downstream ever asks
; how wide a thing really is. sizeof(int) is still 4; a cell holding an int is
; still 8.
;
; The order of the rows is not arbitrary: they ascend by conversion rank, and
; each signed type is immediately followed by its unsigned twin. That is what
; lets "which of these two types wins" be a comparison rather than a matrix.

%include "tsafoshi.inc"

    global  type_size
    global  type_unsigned
    global  type_rank
    global  type_name

TY_NAME             equ 0               ; the text it prints under
TY_NLEN             equ CELL
TY_SIZE             equ CELL * 2        ; sizeof, in bytes
TY_UNS              equ CELL * 3        ; 1 if unsigned
TY_RANK             equ CELL * 4        ; C99's integer conversion rank
TY_ENT              equ CELL * 5

RANK_INT            equ 4               ; the rank the promotions stop at

    section .text

; rdi = type -> rax = its row
row:
    lea     rax, [types]
    imul    rcx, rdi, TY_ENT
    add     rax, rcx
    ret

; rdi = type -> rax = the answer
type_size:
    call    row
    mov     rax, [rax + TY_SIZE]
    ret
type_unsigned:
    call    row
    mov     rax, [rax + TY_UNS]
    ret
type_rank:
    call    row
    mov     rax, [rax + TY_RANK]
    ret

; rdi = type -> rax = its text, rdx = the length
type_name:
    call    row
    mov     rdx, [rax + TY_NLEN]
    mov     rax, [rax + TY_NAME]
    ret

; ---------------------------------------------------------------------------
    section .data

n_void:
    db      "void"
.len                equ $ - n_void
n_bool:
    db      "_Bool"
.len                equ $ - n_bool
n_char:
    db      "char"
.len                equ $ - n_char
n_schar:
    db      "signed char"
.len                equ $ - n_schar
n_uchar:
    db      "unsigned char"
.len                equ $ - n_uchar
n_short:
    db      "short"
.len                equ $ - n_short
n_ushort:
    db      "unsigned short"
.len                equ $ - n_ushort
n_int:
    db      "int"
.len                equ $ - n_int
n_uint:
    db      "unsigned int"
.len                equ $ - n_uint
n_long:
    db      "long"
.len                equ $ - n_long
n_ulong:
    db      "unsigned long"
.len                equ $ - n_ulong

; name, length, sizeof, unsigned, rank. The three char types share a rank, as
; do the two of every other width -- which is C99's ranking exactly, and the
; reason "char versus signed char" needs a tiebreak that rank alone cannot
; give.
    align   8
types:
    dq      n_void, n_void.len, 0, 0, 0
    dq      n_bool, n_bool.len, 1, 1, 1
    dq      n_char, n_char.len, 1, 0, 2
    dq      n_schar, n_schar.len, 1, 0, 2
    dq      n_uchar, n_uchar.len, 1, 1, 2
    dq      n_short, n_short.len, 2, 0, 3
    dq      n_ushort, n_ushort.len, 2, 1, 3
    dq      n_int, n_int.len, 4, 0, RANK_INT
    dq      n_uint, n_uint.len, 4, 1, RANK_INT
    dq      n_long, n_long.len, 8, 0, 5
    dq      n_ulong, n_ulong.len, 8, 1, 5
