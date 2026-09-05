; SPDX-License-Identifier: MIT
;
; Identifier interning. Text goes in, a slot number comes out, and the same
; text always comes back to the same slot -- for the whole session, not just
; the line, which is what lets a variable outlive the statement that made it.
;
; This file knows nothing about values. vars.asm holds those, indexed by the
; slots handed out here, so the compiler deals only in slots and the VM only
; in cells.

%include "tsafoshi.inc"

    global  names_init
    global  name_intern
    global  name_text
    global  name_count

    extern  err_toomanynames
    extern  err_longname

    section .text

; Interns the reserved names before any input is read, so TK_IF, BI_PRINTF and
; the rest are the constants they claim to be. The keywords come first and in
; token order, because the lexer turns a slot below KW_COUNT straight into a
; token kind by adding TK_KW_FIRST to it.
;
; rbx = the entry being interned
names_init:
    push    rbx
    mov     qword [name_count], 0
    lea     rbx, [reserved]
.next:
    mov     rdi, [rbx]
    test    rdi, rdi
    jz      .done
    mov     rsi, [rbx + CELL]
    xor     edx, edx
    call    name_intern
    add     rbx, CELL * 2
    jmp     .next
.done:
    pop     rbx
    ret

; rdi = text, rsi = length, rdx = position for errors -> rax = slot, or -1
name_intern:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     r12, NAME_LEN - 1           ; the terminator needs the last byte
    ja      .too_long

    xor     r14, r14
.search:
    cmp     r14, [name_count]
    jae     .fresh
    lea     rcx, [name_lens]
    movzx   eax, byte [rcx + r14]
    cmp     rax, r12
    jne     .step                       ; different length, cannot match
    mov     rdi, r14
    call    slot_text
    mov     r15, rax
    mov     rcx, r12
.byte:
    test    rcx, rcx
    jz      .found
    dec     rcx
    movzx   eax, byte [r15 + rcx]
    cmp     al, [rbx + rcx]
    je      .byte
.step:
    inc     r14
    jmp     .search

.found:
    mov     rax, r14
    jmp     .out

.fresh:
    cmp     r14, NAME_CAP
    jae     .too_many
    lea     rcx, [name_lens]
    mov     [rcx + r14], r12b
    mov     rdi, r14
    call    slot_text
    xor     ecx, ecx
.copy:
    cmp     rcx, r12
    jae     .terminate
    movzx   edx, byte [rbx + rcx]
    mov     [rax + rcx], dl
    inc     rcx
    jmp     .copy
.terminate:
    mov     byte [rax + rcx], 0
    inc     qword [name_count]
    mov     rax, r14
    jmp     .out

.too_long:
    mov     rdi, r13
    call    err_longname
    jmp     .fail
.too_many:
    mov     rdi, r13
    call    err_toomanynames
.fail:
    mov     rax, -1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = slot -> rax = NUL-terminated text, rdx = length
name_text:
    lea     rcx, [name_lens]
    movzx   edx, byte [rcx + rdi]
    ; fall through

; rdi = slot -> rax = the record's text
slot_text:
    lea     rax, [name_txt]
    imul    rcx, rdi, NAME_LEN
    add     rax, rcx
    ret

; ---------------------------------------------------------------------------
    section .data

; The keywords, in TK_IF .. TK_INT order, then the builtins. Zero ends it.
; This list and the TK_/BI_ constants in tsafoshi.inc are the same fact stated
; twice; KW_COUNT is what keeps them honest.
k_if:
    db      "if"
.len                equ $ - k_if
k_else:
    db      "else"
.len                equ $ - k_else
k_while:
    db      "while"
.len                equ $ - k_while
k_do:
    db      "do"
.len                equ $ - k_do
k_for:
    db      "for"
.len                equ $ - k_for
k_break:
    db      "break"
.len                equ $ - k_break
k_continue:
    db      "continue"
.len                equ $ - k_continue
k_int:
    db      "int"
.len                equ $ - k_int
k_return:
    db      "return"
.len                equ $ - k_return
k_void:
    db      "void"
.len                equ $ - k_void
b_printf:
    db      "printf"
.len                equ $ - b_printf

    align   8
reserved:
    dq      k_if, k_if.len
    dq      k_else, k_else.len
    dq      k_while, k_while.len
    dq      k_do, k_do.len
    dq      k_for, k_for.len
    dq      k_break, k_break.len
    dq      k_continue, k_continue.len
    dq      k_int, k_int.len
    dq      k_return, k_return.len
    dq      k_void, k_void.len
    dq      b_printf, b_printf.len
    dq      0, 0

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
name_count:
    resq    1
name_lens:
    resb    NAME_CAP
name_txt:
    resb    NAME_CAP * NAME_LEN
